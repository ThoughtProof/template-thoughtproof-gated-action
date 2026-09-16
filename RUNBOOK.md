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

Verified 2026-09-16 (Hedera testnet, chain 296):

| What | Link |
| --- | --- |
| Deployer | [`0xEb108a06C1085e9A94940eFFa8eFB119f65F2198`](https://hashscan.io/testnet/account/0xEb108a06C1085e9A94940eFFa8eFB119f65F2198) · account `0.0.10574755` |
| `GatedAction` | [`0x5269A5DC385d4E8648392E6758e50664D07c21F8`](https://hashscan.io/testnet/contract/0x5269A5DC385d4E8648392E6758e50664D07c21F8) |
| Deploy tx | [`0x2264…d8b9`](https://hashscan.io/testnet/transaction/0x2264840649d4c837077b679d7b19844899111f5b9333aea4a930a3303599d8b9) |
| `recordAllow` | [`0x6682…7a97`](https://hashscan.io/testnet/transaction/0x6682fed29ef8f59a53e69996070b5cfeb22b37fa445b5314c721c6e267757a97) SUCCESS |

`executeTransfer` / HBAR-out via `call{value}` reverted `TransferFailed` on this testnet shot (local Hardhat tests still pass the full ALLOW→transfer path). Eligibility tx is deploy + `recordAllow`. Do not claim a completed on-chain HBAR send until a later execute tx is SUCCESS on HashScan.

Remaining local steps:

1. Portal faucet: https://portal.hedera.com/faucet
2. `npm run hardhat:account:generate` (or import ECDSA key used by Scaffold)
3. `npm run hardhat:deploy --network hederaTestnet`
4. Fund `GatedAction` with a tiny HBAR amount
5. `npm run hardhat:demo-gate -- --network hederaTestnet`
6. Optional: `npm run hardhat:verify:testnet`

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
