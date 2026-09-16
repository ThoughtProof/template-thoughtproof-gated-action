# ThoughtProof Gated Action (Scaffold HBAR template)

Fail-closed **HBAR hand** on Hedera for agent workflows:

```
Agent proposes  →  Gate verifies (off-chain)  →  recordAllow  →  executeTransfer
                     BLOCK / missing evidence      (no funds)      (HBAR moves)
```

CLI (once this repo is public):

```bash
npm create scaffold-hbar@latest my-gated-app -- \
  --template <owner>/template-thoughtproof-gated-action \
  --frontend nextjs-app \
  --solidity-framework hardhat \
  --network testnet \
  --package-manager npm
```

Built with [Scaffold HBAR](https://docs.hedera.com/solutions/tools/scaffold-hbar) (`create-scaffold-hbar`).  
**Not** a Hashgraph Online / HOL product. **Not** a Hedera Foundation partnership claim.  
**Not** “Hedera-verified reasoning.” The chain stores compact ALLOW receipts; full traces stay off-chain.

## What you get

| Piece | Role |
| --- | --- |
| `GatedAction.sol` | Treasury + `recordAllow` / `executeTransfer` (fail-closed) |
| Hardhat deploy + tests | Local proof the gate path holds |
| `scripts/demoGateFlow.ts` | Simulated ALLOW → execute (experiment bed) |
| Next.js UI | Wallet + debug + short explainer of the three roles |
| Sample HTS / ERC-20 starters | Unchanged blank-template extras (optional) |

## Roles (do not collapse)

1. **Agent** — reasons / proposes (`proposalHash`)
2. **Gate** — off-chain verifier (ThoughtProof experiment bed, or any compatible tool). Writes ALLOW only when mandate + evidence pass.
3. **Hand** — this contract / executor key. Moves HBAR **only** while an unused, unexpired ALLOW matches recipient + amount.

Production Sentinel is a different surface. This template defaults to a **local simulated ALLOW** so the Scaffold path stays runnable without API keys.

## Quick start

```bash
npm install --legacy-peer-deps
npm run hardhat:test
npm run hardhat:account:generate   # or import

# Terminal 1
npm run hardhat:chain
# Terminal 2
npm run hardhat:deploy --network localhost
npm run hardhat:demo-gate -- --network localhost
# Terminal 3
npm run next:dev
```

Hedera testnet:

```bash
# fund deployer via https://portal.hedera.com/faucet
npm run hardhat:deploy --network hederaTestnet
npm run hardhat:demo-gate -- --network hederaTestnet
npm run hardhat:verify:testnet
```

Optional role split:

```bash
GATED_RECORDER=0x... GATED_EXECUTOR=0x... npm run hardhat:deploy --network hederaTestnet
```

## Contract surface

- `recordAllow(proposalHash, evidenceHash, recipient, amountWei, expiresAt)` — **recorder** only
- `executeTransfer(allowId, recipient, amountWei)` — **executor** only; reverts if missing / used / expired / mismatch / empty treasury
- `rescue` — owner only (testnet recovery, not a gate bypass for the happy path)

Events: `AllowRecorded`, `AllowExecuted`, `AllowExpiredSkipped`.

## Disclaimer

Experimental. Not audited. Testnet / small amounts only.  
No claim that Hedera consensus validates model reasoning.  
Gate decision quality is entirely off-chain.

## License

MIT (Scaffold HBAR baseline + this template’s additions).

## Links

- Scaffold HBAR docs: https://docs.hedera.com/solutions/tools/scaffold-hbar
- Hedera faucet: https://portal.hedera.com/faucet
- HashScan: https://hashscan.io/
- ThoughtProof (gate product, separate): https://www.thoughtproof.ai/
