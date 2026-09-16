// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GatedAction
/// @notice Fail-closed HBAR hand on Hedera: execute only after an off-chain gate ALLOW is recorded.
/// @dev ThoughtProof / Sentinel (or any compatible verifier) is off-chain. This contract does **not**
///      call an oracle and does **not** claim "Hedera-verified reasoning". It stores a compact
///      ALLOW receipt (proposalHash + evidenceHash + expiresAt) and then lets the executor pull HBAR.
///
/// Flow:
///   1. Agent proposes an action (off-chain) → proposalHash
///   2. Gate verifies mandate + evidence → ALLOW receipt (evidenceHash, expiresAt)
///   3. Authorized recorder calls recordAllow(...)
///   4. Executor calls executeTransfer only while the ALLOW is live and unused
///
/// Experimental template. Testnet / small amounts only. Not production Sentinel.
contract GatedAction is Ownable, ReentrancyGuard {
    /// @notice Who may write ALLOW receipts (gate operator / automation key).
    address public recorder;

    /// @notice Who may execute after ALLOW (agent executor / MCP hand).
    address public executor;

    uint256 public allowCount;
    uint256 public executedCount;

    struct AllowReceipt {
        bytes32 proposalHash;
        bytes32 evidenceHash;
        address recipient;
        uint256 amountWei;
        uint64 expiresAt;
        bool used;
        bool exists;
    }

    /// allowId => receipt
    mapping(uint256 => AllowReceipt) public allows;

    /// proposalHash => allowId (0 = none). Prevents double-recording the same proposal.
    mapping(bytes32 => uint256) public allowIdByProposal;

    event RecorderUpdated(address indexed previous, address indexed current);
    event ExecutorUpdated(address indexed previous, address indexed current);
    event Funded(address indexed from, uint256 amount);
    event AllowRecorded(
        uint256 indexed allowId,
        bytes32 indexed proposalHash,
        bytes32 evidenceHash,
        address indexed recipient,
        uint256 amountWei,
        uint64 expiresAt
    );
    event AllowExecuted(uint256 indexed allowId, bytes32 indexed proposalHash, address indexed recipient, uint256 amountWei);
    event AllowExpiredSkipped(uint256 indexed allowId, bytes32 indexed proposalHash);

    error ZeroAddress();
    error NotRecorder();
    error NotExecutor();
    error InvalidAmount();
    error InvalidExpiry();
    error ProposalAlreadyRecorded();
    error AllowMissing();
    error AllowAlreadyUsed();
    error AllowExpired();
    error RecipientMismatch();
    error AmountMismatch();
    error InsufficientTreasury();
    error TransferFailed();

    modifier onlyRecorder() {
        if (msg.sender != recorder) revert NotRecorder();
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert NotExecutor();
        _;
    }

    constructor(address initialOwner, address initialRecorder, address initialExecutor) Ownable(initialOwner) {
        if (initialOwner == address(0) || initialRecorder == address(0) || initialExecutor == address(0)) {
            revert ZeroAddress();
        }
        recorder = initialRecorder;
        executor = initialExecutor;
        emit RecorderUpdated(address(0), initialRecorder);
        emit ExecutorUpdated(address(0), initialExecutor);
    }

    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    function setRecorder(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit RecorderUpdated(recorder, next);
        recorder = next;
    }

    function setExecutor(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit ExecutorUpdated(executor, next);
        executor = next;
    }

    /// @notice Record an off-chain ALLOW. Does not move funds.
    /// @param proposalHash Hash of the agent proposal (e.g. keccak of canonical JSON).
    /// @param evidenceHash Hash of gate evidence pack / verdict envelope (off-chain full trace).
    /// @param recipient Intended HBAR recipient for this allow.
    /// @param amountWei Exact amount authorized (wei / tinybar-as-wei on EVM mirror).
    /// @param expiresAt Unix seconds; execute must happen strictly before this.
    function recordAllow(
        bytes32 proposalHash,
        bytes32 evidenceHash,
        address recipient,
        uint256 amountWei,
        uint64 expiresAt
    ) external onlyRecorder returns (uint256 allowId) {
        if (recipient == address(0)) revert ZeroAddress();
        if (amountWei == 0) revert InvalidAmount();
        if (expiresAt <= block.timestamp) revert InvalidExpiry();
        if (allowIdByProposal[proposalHash] != 0) revert ProposalAlreadyRecorded();

        allowId = ++allowCount;
        allows[allowId] = AllowReceipt({
            proposalHash: proposalHash,
            evidenceHash: evidenceHash,
            recipient: recipient,
            amountWei: amountWei,
            expiresAt: expiresAt,
            used: false,
            exists: true
        });
        allowIdByProposal[proposalHash] = allowId;

        emit AllowRecorded(allowId, proposalHash, evidenceHash, recipient, amountWei, expiresAt);
    }

    /// @notice Execute only while ALLOW is live, unused, and parameters match.
    function executeTransfer(
        uint256 allowId,
        address recipient,
        uint256 amountWei
    ) external onlyExecutor nonReentrant {
        AllowReceipt storage receipt = allows[allowId];
        if (!receipt.exists) revert AllowMissing();
        if (receipt.used) revert AllowAlreadyUsed();
        if (block.timestamp >= receipt.expiresAt) {
            emit AllowExpiredSkipped(allowId, receipt.proposalHash);
            revert AllowExpired();
        }
        if (recipient != receipt.recipient) revert RecipientMismatch();
        if (amountWei != receipt.amountWei) revert AmountMismatch();
        if (address(this).balance < amountWei) revert InsufficientTreasury();

        receipt.used = true;
        executedCount += 1;

        (bool ok, ) = recipient.call{ value: amountWei }("");
        if (!ok) revert TransferFailed();

        emit AllowExecuted(allowId, receipt.proposalHash, recipient, amountWei);
    }

    /// @notice Owner rescue for stranded testnet funds (not a bypass of the gate path).
    function rescue(address to, uint256 amountWei) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amountWei == 0 || amountWei > address(this).balance) revert InvalidAmount();
        (bool ok, ) = to.call{ value: amountWei }("");
        if (!ok) revert TransferFailed();
    }

    function isAllowLive(uint256 allowId) external view returns (bool) {
        AllowReceipt storage receipt = allows[allowId];
        return receipt.exists && !receipt.used && block.timestamp < receipt.expiresAt;
    }
}
