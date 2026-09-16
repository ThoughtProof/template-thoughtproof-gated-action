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

    /// @notice Credit HBAR via an EVM contract call (function selector + msg.value).
    /// @dev Bare `sendTransaction({to, value})` on Hedera is often a CryptoTransfer to the
    ///      account, which shows up on Hashio/mirror but is **not** spendable via Solidity
    ///      `transfer`/`call{value}`. Always fund through `deposit` (or another payable fn).
    function deposit() external payable {
        if (msg.value == 0) revert InvalidAmount();
        emit Funded(msg.sender, msg.value);
    }

    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    function treasuryBalance() external view returns (uint256) {
        return address(this).balance;
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

        receipt.used = true;
        executedCount += 1;

        // Hedera tutorial path: Solidity `.transfer` after HBAR was credited via payable fn.
        // `call{value}` against CryptoTransfer-credited account HBAR returns false here.
        _sendHbar(payable(recipient), amountWei);

        emit AllowExecuted(allowId, receipt.proposalHash, recipient, amountWei);
    }

    /// @notice Owner rescue for stranded testnet funds (not a bypass of the gate path).
    function rescue(address to, uint256 amountWei) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amountWei == 0) revert InvalidAmount();
        _sendHbar(payable(to), amountWei);
    }

    function _sendHbar(address payable to, uint256 amountWei) internal {
        // JSON-RPC / ethers use weibar (1e18 per HBAR). On live Hedera, Solidity
        // `address.balance` / `.transfer` use tinybars (1e8 per HBAR). 1 tinybar = 1e10 wei.
        // Hardhat (even a Hedera fork) stays in wei — only convert when the two views disagree.
        uint256 nativeAmount = amountWei;
        uint256 bal = address(this).balance;
        uint256 weibarPerTinybar = 10_000_000_000;
        if (bal < amountWei && amountWei >= weibarPerTinybar && bal >= amountWei / weibarPerTinybar) {
            nativeAmount = amountWei / weibarPerTinybar;
        }
        to.transfer(nativeAmount);
    }

    function isAllowLive(uint256 allowId) external view returns (bool) {
        AllowReceipt storage receipt = allows[allowId];
        return receipt.exists && !receipt.used && block.timestamp < receipt.expiresAt;
    }
}
