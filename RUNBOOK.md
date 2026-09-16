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

1. Portal account + faucet: https://portal.hedera.com/faucet  
2. `npm run hardhat:account:generate` (or import ECDSA key used by Scaffold)  
3. `npm run hardhat:deploy --network hederaTestnet`  
4. Fund `GatedAction` with a tiny HBAR amount (same deployer send to contract address)  
5. `npm run hardhat:demo-gate -- --network hederaTestnet`  
6. Copy **both** tx hashes (`recordAllow`, `executeTransfer`) + contract address into the bounty submission  
7. Optional: `npm run hardhat:verify:testnet`

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
