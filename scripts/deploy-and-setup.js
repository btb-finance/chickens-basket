const { ethers } = require("hardhat");
require('dotenv').config();

// ABI imports for USDC
const IERC20_ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)"
];

async function main() {
  console.log("Starting comprehensive deployment and setup process...");
  console.log("=======================================================");
  
  // Get the signer
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying and setting up with account: ${deployer.address}`);
  
  // Load environment variables
  const usdcAddress = process.env.usdc_address;
  const aavePoolAddress = process.env.aave_pool_address;
  const aUsdcTokenAddress = process.env.ausdc_token_address;
  const minLiquidityBuffer = process.env.min_liquidity_buffer;
  const feeAddress = process.env.fee_address;
  const startAmount = process.env.set_start;
  
  // Validate required environment variables
  if (!usdcAddress || !aavePoolAddress || !aUsdcTokenAddress || !minLiquidityBuffer || !feeAddress || !startAmount) {
    throw new Error("Missing required environment variables. Please check your .env file.");
  }
  
  console.log("\n--- STEP 1: Deploying CHICKS Contract ---");
  // Get the contract factory
  const CHICKS = await ethers.getContractFactory("CHICKS");
  
  // Deploy the contract with constructor arguments
  console.log("Deploying CHICKS token...");
  const chicks = await CHICKS.deploy(usdcAddress);
  
  // Wait for deployment to finish
  await chicks.waitForDeployment();
  
  // Get the deployed contract address
  const chicksAddress = await chicks.getAddress();
  console.log(`CHICKS token deployed to: ${chicksAddress}`);
  
  console.log("\n--- STEP 2: Verifying Contract ---");
  try {
    console.log("Waiting 30 seconds before verification to ensure contract is registered on the blockchain...");
    await new Promise(resolve => setTimeout(resolve, 30000));
    
    console.log("Verifying contract on Blockscout...");
    await hre.run("verify:verify", {
      address: chicksAddress,
      constructorArguments: [usdcAddress],
    });
    console.log("Contract verified successfully");
  } catch (error) {
    console.warn("Verification failed, but continuing with setup:", error.message);
  }
  
  console.log("\n--- STEP 3: Setting Minimum Liquidity Buffer ---");
  const setMinLiquidityBufferTx = await chicks.setMinLiquidityBuffer(minLiquidityBuffer);
  await setMinLiquidityBufferTx.wait();
  console.log(`Minimum liquidity buffer set to: ${minLiquidityBuffer}`);
  
  console.log("\n--- STEP 4: Setting Fee Address ---");
  const setFeeAddressTx = await chicks.setFeeAddress(feeAddress);
  await setFeeAddressTx.wait();
  console.log(`Fee address set to: ${feeAddress}`);
  
  console.log("\n--- STEP 5: Setting Start Amount ---");
  const setStartTx = await chicks.setStart(startAmount);
  await setStartTx.wait();
  console.log(`Contract started with initial amount: ${startAmount}`);
  
  console.log("\n--- STEP 6: Sending 1 USDC to Contract ---");
  // Get USDC contract instance
  const usdc = new ethers.Contract(usdcAddress, IERC20_ABI, deployer);
  
  // Check USDC balance
  const usdcBalance = await usdc.balanceOf(deployer.address);
  console.log(`Current USDC balance: ${ethers.formatUnits(usdcBalance, 6)}`);
  
  // Send 1 USDC to the contract
  const oneUSDC = ethers.parseUnits("1", 6);
  const transferTx = await usdc.transfer(chicksAddress, oneUSDC);
  const transferReceipt = await transferTx.wait();
  console.log(`Direct USDC transfer successful! Transaction hash: ${transferReceipt.hash}`);
  
  console.log("\n--- STEP 7: Approving USDC Spending ---");
  const approveTx = await usdc.approve(chicksAddress, ethers.parseUnits("1000000", 6));
  await approveTx.wait();
  console.log("USDC approved successfully");
  
  console.log("\n--- STEP 8: Buying CHICKS with 1 USDC ---");
  // Get expected CHICKS tokens
  const expectedChicks = await chicks.getBuyChicks(oneUSDC);
  console.log(`Expected CHICKS tokens: ${ethers.formatEther(expectedChicks)}`);
  
  // Execute buy transaction
  const buyTx = await chicks.buy(deployer.address, oneUSDC);
  const buyReceipt = await buyTx.wait();
  console.log(`Purchase successful! Transaction hash: ${buyReceipt.hash}`);
  
  // Get updated CHICKS balance
  const chicksBalance = await chicks.balanceOf(deployer.address);
  console.log(`New CHICKS balance: ${ethers.formatEther(chicksBalance)}`);
  
  console.log("\n--- STEP 9: Setting up AAVE Integration ---");
  // Set AAVE Pool
  const setPoolTx = await chicks.setAavePool(aavePoolAddress);
  await setPoolTx.wait();
  console.log(`AAVE Pool set to: ${aavePoolAddress}`);
  
  // Set aUSDC Token
  const setAUsdcTx = await chicks.setAUsdcToken(aUsdcTokenAddress);
  await setAUsdcTx.wait();
  console.log(`aUSDC Token set to: ${aUsdcTokenAddress}`);
  
  // Enable AAVE
  const enableAaveTx = await chicks.setAaveEnabled(true);
  await enableAaveTx.wait();
  console.log("AAVE integration enabled");
  
  console.log("\n--- STEP 10: Buying 10 USDC worth of CHICKS ---");
  // Buy 10 USDC worth of CHICKS
  const tenUSDC = ethers.parseUnits("10", 6);
  
  // Check if we have enough USDC balance
  const currentUsdcBalance = await usdc.balanceOf(deployer.address);
  console.log(`Current USDC balance: ${ethers.formatUnits(currentUsdcBalance, 6)}`);
  
  if (currentUsdcBalance >= tenUSDC) {
    // Get expected CHICKS tokens for 10 USDC
    const expectedChicksForTen = await chicks.getBuyChicks(tenUSDC);
    console.log(`Expected CHICKS tokens for 10 USDC: ${ethers.formatEther(expectedChicksForTen)}`);
    
    // Execute buy transaction for 10 USDC
    const buyTenTx = await chicks.buy(deployer.address, tenUSDC);
    const buyTenReceipt = await buyTenTx.wait();
    console.log(`Purchase of 10 USDC successful! Transaction hash: ${buyTenReceipt.hash}`);
    
    // Get updated CHICKS balance
    const finalChicksBalance = await chicks.balanceOf(deployer.address);
    console.log(`Final CHICKS balance: ${ethers.formatEther(finalChicksBalance)}`);
  } else {
    console.warn(`Insufficient USDC balance for 10 USDC purchase. Current balance: ${ethers.formatUnits(currentUsdcBalance, 6)}`);
  }
  
  console.log("\n=======================================================");
  console.log("Deployment and setup complete!");
  console.log(`CHICKS Contract Address: ${chicksAddress}`);
  console.log(`View your contract on Blockscout: https://base-sepolia.blockscout.com/address/${chicksAddress}`);
  
  // Save the contract address to .env file
  const fs = require('fs');
  fs.appendFileSync('.env', `\nCHICKS_ADDRESS=${chicksAddress}\n`);
  console.log("Contract address saved to .env file");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
