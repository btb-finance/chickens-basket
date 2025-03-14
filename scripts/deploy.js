// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
const hre = require("hardhat");
require('dotenv').config();

async function main() {
  // Get the contract factory
  const CHICKS = await hre.ethers.getContractFactory("CHICKS");
  
  // Deploy the contract with constructor arguments
  console.log("Deploying CHICKS token...");
  const chicks = await CHICKS.deploy(
    process.env.usdc_address         // USDC token address
  );
  
  // Wait for deployment to finish
  await chicks.waitForDeployment();
  
  // Get the deployed contract address
  const chicksAddress = await chicks.getAddress();
  console.log(`CHICKS token deployed to: ${chicksAddress}`);
  
  // Set up the contract with initial configuration
  console.log("Setting up initial configuration...");
  
  // Set fee address
  const setFeeAddressTx = await chicks.setFeeAddress(process.env.fee_address);
  await setFeeAddressTx.wait();
  console.log(`Fee address set to: ${process.env.fee_address}`);
  
  // Set minimum liquidity buffer
  const setMinLiquidityBufferTx = await chicks.setMinLiquidityBuffer(process.env.min_liquidity_buffer);
  await setMinLiquidityBufferTx.wait();
  console.log(`Minimum liquidity buffer set to: ${process.env.min_liquidity_buffer}`);
  
  // Set start with initial USDC amount
  const setStartTx = await chicks.setStart(process.env.set_start);
  await setStartTx.wait();
  console.log(`Contract started with initial amount: ${process.env.set_start}`);
  
  // Verify contract on Etherscan if not on a local network
  if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
    console.log("Proceeding with contract verification...");
    // Add a small delay to ensure the contract is deployed
    await new Promise(resolve => setTimeout(resolve, 30000)); // 30 seconds delay
    
    console.log("Verifying contract on Blockscout via Sourcify...");
    try {
      // Try Sourcify verification first (works better with Blockscout)
      await hre.run("sourcify", {
        address: chicksAddress,
        network: hre.network.name
      });
      console.log("Contract verified via Sourcify");
    } catch (error) {
      console.log("Sourcify verification failed, trying Etherscan verification...");
      try {
        await hre.run("verify:verify", {
          address: chicksAddress,
          constructorArguments: [
            process.env.usdc_address
          ],
        });
        console.log("Contract verified on Etherscan");
      } catch (verifyError) {
        console.error("Verification failed:", verifyError);
      }
    }
  }
  
  console.log("Deployment and setup complete!");
  console.log("View your contract on Blockscout: https://base-sepolia.blockscout.com/address/" + chicksAddress);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });