/**
 * Local / testnet demo of the fail-closed path (no external API keys required).
 *
 * Usage (after deploy + fund):
 *   npx hardhat run scripts/demoGateFlow.ts --network localhost
 *   npx hardhat run scripts/demoGateFlow.ts --network hederaTestnet
 *
 * Env (optional):
 *   DEMO_RECIPIENT=0x...
 *   DEMO_AMOUNT_ETH=0.01
 *
 * This script **simulates** an off-chain gate decision. It does not call production Sentinel.
 * Experiment bed pattern: proposal → fake ALLOW hashes → recordAllow → executeTransfer.
 */
import hre from "hardhat";

async function main() {
  const { ethers, deployments } = hre;
  const [signer] = await ethers.getSigners();
  const dep = await deployments.get("GatedAction");
  const gated = await ethers.getContractAt("GatedAction", dep.address, signer);

  const recipient = (process.env.DEMO_RECIPIENT || signer.address).trim();
  const amount = ethers.parseEther(process.env.DEMO_AMOUNT_ETH || "0.01");
  const proposal = {
    kind: "hbar_transfer",
    to: recipient,
    amountWei: amount.toString(),
    note: "scaffold-hbar gated demo — experiment bed, not prod Sentinel",
  };
  const proposalHash = ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(proposal)));
  const evidenceHash = ethers.keccak256(
    ethers.toUtf8Bytes(JSON.stringify({ verdict: "ALLOW", gate: "local-demo", ts: Date.now() })),
  );
  const expiresAt = BigInt(Math.floor(Date.now() / 1000) + 30 * 60);

  console.log("GatedAction", dep.address);
  console.log("signer", signer.address);
  console.log("proposalHash", proposalHash);

  // fund if empty
  const bal = await ethers.provider.getBalance(dep.address);
  if (bal < amount) {
    const top = amount - bal + ethers.parseEther("0.001");
    console.log("funding treasury", top.toString());
    await (await signer.sendTransaction({ to: dep.address, value: top })).wait();
  }

  const existing = await gated.allowIdByProposal(proposalHash);
  let allowId = existing;
  if (existing === 0n) {
    const tx = await gated.recordAllow(proposalHash, evidenceHash, recipient, amount, expiresAt, {
    gasLimit: 500_000,
  });
  const rc = await tx.wait();
  console.log("recordAllow tx", rc?.hash);
  allowId = await gated.allowIdByProposal(proposalHash);
  } else {
    console.log("proposal already recorded as allowId", existing.toString());
  }

  const live = await gated.isAllowLive(allowId);
  console.log("allowId", allowId.toString(), "live", live);
  if (!live) {
    throw new Error("ALLOW not live — check expiry / used");
  }

  const before = await ethers.provider.getBalance(recipient);
  const ex = await gated.executeTransfer(allowId, recipient, amount, { gasLimit: 1_000_000 });
  const exRc = await ex.wait();
  const after = await ethers.provider.getBalance(recipient);
  console.log("executeTransfer tx", exRc?.hash);
  console.log("recipient delta wei", (after - before).toString());
  console.log("done — gate path exercised (simulated ALLOW, not prod Sentinel)");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
