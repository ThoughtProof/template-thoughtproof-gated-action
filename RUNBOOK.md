# RUNBOOK — Gated Action template

End-to-end checks for reviewers and agents. Keep claims honest.

## 0. Claims hygiene

| Allowed | Forbidden |
| --- | --- |
| “Execute only after on-chain ALLOW receipt” | “Hedera-verified reasoning” |
| “Experiment bed / simulated gate in demo script” | “Production Sentinel by default” |
| “ThoughtProof-compatible hashes” | “HOL partnership” / “Hedera Foundation partner” from this template alone |
| Testnet tx hash as evidence | Mainnet / live-capital path without explicit operator intent |

## 1. Unit tests (no network)

```bash
npm install --legacy-peer-deps
npm run hardhat:test
```

Expect `GatedAction` cases: missing ALLOW, role checks, happy path once, expiry, mismatch, duplicate proposal.

## 2. Local chain demo

```bash
npm run hardhat:chain          # terminal A
npm run hardhat:deploy --network localhost
npm run hardhat:demo-gate -- --network localhost
```

Pass criteria:

- `recordAllow` tx mined
- `executeTransfer` tx mined
- recipient balance increases by `DEMO_AMOUNT_ETH` (default `0.01`)
- second execute on same `allowId` reverts `AllowAlreadyUsed`

## 3. Hedera testnet (submission evidence)

Verified 2026-09-16 (Hedera testnet, chain 296). Mirror `SUCCESS` on deploy, `recordAllow`, and `executeTransfer`. Contract leftover **100000 tinybars (0.001 HBAR)** after sending **0.01 HBAR** (deposited 0.011).

- Deployer: https://hashscan.io/testnet/account/0xEb108a06C1085e9A94940eFFa8eFB119f65F2198 (`0.0.10574755`)
- `GatedAction`: https://hashscan.io/testnet/contract/0x41DE479dB2a7b7362430c114B7e235FEfB8700b2 (`0.0.10575012`)
- Deploy: https://hashscan.io/testnet/tx/0x9447a0de5d8845ea9364558ba1518528074345ef281ce70b9f1b1cee43fdb008
- `recordAllow`: https://hashscan.io/testnet/tx/0x18c9fa29da6192ffcf3851e9cceb127460fb801ac185ce5e0878771cb83e6180
- `executeTransfer`: https://hashscan.io/testnet/tx/0x68b56c8070f168250a28e1588ddff3441eec705592222f1c96f2aac56d1e5c44

Fund only via `deposit()` (payable). Live Hedera Solidity value ops are **tinybars**; ethers `parseEther` is **weibar**. `_sendHbar` converts when the two disagree. Hardhat stays in wei.

```bash
npm run hardhat:deploy --network hederaTestnet
npm run hardhat:demo-gate -- --network hederaTestnet
```

## 4. Wiring a real gate (optional, post-scaffold)

Replace demo hashes:

1. Canonicalize the agent proposal JSON → `proposalHash = keccak256(bytes)`
2. Run your verifier (ThoughtProof bed / MCP / HTTP). On **ALLOW**, set `evidenceHash` to the hash of the verdict envelope you retain off-chain.
3. Call `recordAllow` from the **recorder** key only if verdict is ALLOW and mandate matches.
4. Call `executeTransfer` from the **executor** key (agent hand / automation).

On BLOCK or missing evidence: **do not** call `recordAllow`. No on-chain noise required.

## 5. Frontend smoke

```bash
npm run next:dev
```

Open `/` — roles copy visible. Open `/debug` — `GatedAction` after deploy ABIs refresh.

## 6. Bounty packaging checklist

- [ ] Public GitHub repo, MIT, root `template.json`
- [ ] `README.md` + `AGENTS.md` + this `RUNBOOK.md`
- [ ] `npm run hardhat:test` green in CI or paste log
- [ ] One Hedera **testnet** tx pair (allow + execute) on HashScan
- [ ] No production API keys in repo
- [ ] No HOL co-brand; no “Foundation partnership” wording
