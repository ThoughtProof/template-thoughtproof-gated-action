import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { DeployFunction } from "hardhat-deploy/types";

import { getDeployGasPrice } from "../utils/getDeployGasPrice";

/**
 * Deploys GatedAction.
 * Default: deployer is owner + recorder + executor (local/demo).
 * Override with env:
 *   GATED_RECORDER=0x...
 *   GATED_EXECUTOR=0x...
 */
const deployGatedAction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  const recorder = (process.env.GATED_RECORDER || deployer).trim();
  const executor = (process.env.GATED_EXECUTOR || deployer).trim();

  await deploy("GatedAction", {
    from: deployer,
    args: [deployer, recorder, executor],
    log: true,
    autoMine: true,
    gasLimit: "3000000",
    gasPrice: await getDeployGasPrice(hre),
  });
};

deployGatedAction.tags = ["GatedAction"];
export default deployGatedAction;
