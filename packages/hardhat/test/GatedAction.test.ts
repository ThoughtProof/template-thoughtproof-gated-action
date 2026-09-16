import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("GatedAction", function () {
  async function deployFixture() {
    const [owner, recorder, executor, alice, bob] = await ethers.getSigners();
    const GatedAction = await ethers.getContractFactory("GatedAction");
    const gated = await GatedAction.deploy(owner.address, recorder.address, executor.address);
    await gated.waitForDeployment();

    // fund treasury via deposit (Hedera-spendable path). receive() still exists for local ETH-style sends.
    await gated.deposit({ value: ethers.parseEther("10") });

    const proposalHash = ethers.keccak256(ethers.toUtf8Bytes('{"action":"transfer","to":"alice","amt":"1"}'));
    const evidenceHash = ethers.keccak256(ethers.toUtf8Bytes('{"verdict":"ALLOW","gate":"experiment-bed"}'));
    const amount = ethers.parseEther("1");
    const expiresAt = BigInt((await time.latest()) + 3600);

    return { gated, owner, recorder, executor, alice, bob, proposalHash, evidenceHash, amount, expiresAt };
  }

  it("sets roles", async function () {
    const { gated, owner, recorder, executor } = await deployFixture();
    expect(await gated.owner()).to.equal(owner.address);
    expect(await gated.recorder()).to.equal(recorder.address);
    expect(await gated.executor()).to.equal(executor.address);
  });

  it("blocks execute without ALLOW", async function () {
    const { gated, executor, alice, amount } = await deployFixture();
    await expect(gated.connect(executor).executeTransfer(1, alice.address, amount)).to.be.revertedWithCustomError(
      gated,
      "AllowMissing",
    );
  });

  it("blocks recordAllow from non-recorder", async function () {
    const { gated, alice, proposalHash, evidenceHash, amount, expiresAt } = await deployFixture();
    await expect(
      gated.connect(alice).recordAllow(proposalHash, evidenceHash, alice.address, amount, expiresAt),
    ).to.be.revertedWithCustomError(gated, "NotRecorder");
  });

  it("ALLOW then execute transfers HBAR once", async function () {
    const { gated, recorder, executor, alice, proposalHash, evidenceHash, amount, expiresAt } = await deployFixture();

    await expect(
      gated.connect(recorder).recordAllow(proposalHash, evidenceHash, alice.address, amount, expiresAt),
    )
      .to.emit(gated, "AllowRecorded")
      .withArgs(1n, proposalHash, evidenceHash, alice.address, amount, expiresAt);

    const before = await ethers.provider.getBalance(alice.address);
    await expect(gated.connect(executor).executeTransfer(1, alice.address, amount))
      .to.emit(gated, "AllowExecuted")
      .withArgs(1n, proposalHash, alice.address, amount);
    const after = await ethers.provider.getBalance(alice.address);
    expect(after - before).to.equal(amount);

    // second execute blocked
    await expect(gated.connect(executor).executeTransfer(1, alice.address, amount)).to.be.revertedWithCustomError(
      gated,
      "AllowAlreadyUsed",
    );
  });

  it("rejects expired ALLOW", async function () {
    const { gated, recorder, executor, alice, proposalHash, evidenceHash, amount } = await deployFixture();
    const shortExpiry = BigInt((await time.latest()) + 10);
    await gated.connect(recorder).recordAllow(proposalHash, evidenceHash, alice.address, amount, shortExpiry);
    await time.increase(20);
    await expect(gated.connect(executor).executeTransfer(1, alice.address, amount)).to.be.revertedWithCustomError(
      gated,
      "AllowExpired",
    );
  });

  it("rejects recipient/amount mismatch", async function () {
    const { gated, recorder, executor, alice, bob, proposalHash, evidenceHash, amount, expiresAt } =
      await deployFixture();
    await gated.connect(recorder).recordAllow(proposalHash, evidenceHash, alice.address, amount, expiresAt);
    await expect(gated.connect(executor).executeTransfer(1, bob.address, amount)).to.be.revertedWithCustomError(
      gated,
      "RecipientMismatch",
    );
    await expect(
      gated.connect(executor).executeTransfer(1, alice.address, amount + 1n),
    ).to.be.revertedWithCustomError(gated, "AmountMismatch");
  });

  it("rejects duplicate proposalHash", async function () {
    const { gated, recorder, alice, proposalHash, evidenceHash, amount, expiresAt } = await deployFixture();
    await gated.connect(recorder).recordAllow(proposalHash, evidenceHash, alice.address, amount, expiresAt);
    await expect(
      gated.connect(recorder).recordAllow(proposalHash, evidenceHash, alice.address, amount, expiresAt),
    ).to.be.revertedWithCustomError(gated, "ProposalAlreadyRecorded");
  });
});
