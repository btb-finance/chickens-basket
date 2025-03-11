const { ethers } = require("ethers");
require("dotenv").config();
const fs = require("fs");

// Get CHICKS ABI from artifacts if available
function getChicksAbi() {
  try {
    const artifactPath = './artifacts/contracts/chicks.sol/CHICKS.json';
    if (fs.existsSync(artifactPath)) {
      const artifact = require(artifactPath);
      return artifact.abi;
    }
  } catch (error) {
    console.warn("Could not load CHICKS ABI from artifacts, using minimal ABI");
  }
  
  // Fallback to minimal ABI with the AAVE integration functions
  return [
    "function setAUsdcToken(address _aUsdcToken) external",
    "function setAaveEnabled(bool _enabled) external",
    "function setAavePool(address _aavePool) external"
  ];
}

async function main() {
    // Get the deployed contract address from environment variables
    const chicksAddress = process.env.CHICKS_ADDRESS;
    
    if (!chicksAddress) {
        throw new Error("Please set CHICKS_ADDRESS in your .env file");
    }
    
    // Get AAVE-related addresses from environment variables
    const aavePoolAddress = process.env.aave_pool_address;
    const aUsdcTokenAddress = process.env.ausdc_token_address;
    
    if (!aavePoolAddress || !aUsdcTokenAddress) {
        throw new Error("Please set aave_pool_address and ausdc_token_address in your .env file");
    }

    // Set up provider and signer
    const provider = new ethers.JsonRpcProvider(process.env.rpc_url);
    const signer = new ethers.Wallet(process.env.private_key, provider);
    console.log("Using account:", signer.address);

    // Get contract instance
    const chicksAbi = getChicksAbi();
    const chicks = new ethers.Contract(chicksAddress, chicksAbi, signer);

    // Step 1: Set aUSDC token address
    console.log(`Setting aUSDC token address to: ${aUsdcTokenAddress}`);
    try {
        const setAUsdcTokenTx = await chicks.setAUsdcToken(aUsdcTokenAddress);
        await setAUsdcTokenTx.wait();
        console.log("aUSDC token address set successfully");
    } catch (error) {
        console.error("Error setting aUSDC token address:", error.message);
        throw error;
    }

    // Step 2: Set AAVE pool address
    console.log(`Setting AAVE pool address to: ${aavePoolAddress}`);
    try {
        const setAavePoolTx = await chicks.setAavePool(aavePoolAddress);
        await setAavePoolTx.wait();
        console.log("AAVE pool address set successfully");
    } catch (error) {
        console.error("Error setting AAVE pool address:", error.message);
        throw error;
    }

    // Step 3: Enable AAVE integration
    console.log("Enabling AAVE integration...");
    try {
        const setAaveEnabledTx = await chicks.setAaveEnabled(true);
        await setAaveEnabledTx.wait();
        console.log("AAVE integration enabled successfully");
    } catch (error) {
        console.error("Error enabling AAVE integration:", error.message);
        throw error;
    }

    console.log("AAVE integration setup complete!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });