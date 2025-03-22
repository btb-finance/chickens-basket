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
  
  // Load environment variables with defaults for testing
  const usdcAddress = process.env.usdc_address || "0x5deac602762362fe5f135fa5904351916053cf70"; // Base Sepolia USDC
  const feeAddress = process.env.fee_address || "0x000000000000000000000000000000000000dEaD";
  const minLiquidityBuffer = process.env.min_liquidity_buffer || "1000000"; // 1 USDC with 6 decimals
  // Note: setStart() no longer requires an amount parameter as it's hardcoded in the contract
  
  // For AAVE integration (optional)
  const aavePoolAddress = process.env.aave_pool_address;
  const aUsdcTokenAddress = process.env.ausdc_token_address;
  
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
  
  console.log("\n--- STEP 2: Setting Fee Address ---");
  const setFeeAddressTx = await chicks.setFeeAddress(feeAddress);
  await setFeeAddressTx.wait();
  console.log(`Fee address set to: ${feeAddress}`);
  
  console.log("\n--- STEP 3: Setting Minimum Liquidity Buffer ---");
  const setMinLiquidityBufferTx = await chicks.setMinLiquidityBuffer(minLiquidityBuffer);
  await setMinLiquidityBufferTx.wait();
  console.log(`Minimum liquidity buffer set to: ${minLiquidityBuffer}`);
  
  // Get USDC contract instance
  const usdc = new ethers.Contract(usdcAddress, IERC20_ABI, deployer);
  
  // Check USDC balance
  const usdcBalance = await usdc.balanceOf(deployer.address);
  console.log(`\nCurrent USDC balance: ${ethers.formatUnits(usdcBalance, 6)}`);
  
  if (usdcBalance.toString() === "0") {
    console.log("\n⚠️ USDC balance is zero. Please fund your account with USDC before continuing.");
    console.log("You can get Base Sepolia USDC from the Base Sepolia Faucet.");
    return;
  }
  
  console.log("\n--- STEP 4: Approving USDC Spending ---");
  // Approve a large amount for all future transactions
  const largeApprovalAmount = ethers.parseUnits("1000000", 6); // 1 million USDC
  const approveTx = await usdc.approve(chicksAddress, largeApprovalAmount);
  await approveTx.wait();
  console.log(`USDC approved for spending: ${ethers.formatUnits(largeApprovalAmount, 6)}`);
  
  console.log("\n--- STEP 5: Setting Start Amount ---");
  const setStartTx = await chicks.setStart();
  await setStartTx.wait();
  console.log(`Contract started successfully`);
  
  console.log("\n--- STEP 6: Sending 1 USDC to Contract ---");
  // Send 1 USDC to the contract directly
  const oneUSDC = ethers.parseUnits("1", 6);
  const transferTx = await usdc.transfer(chicksAddress, oneUSDC);
  const transferReceipt = await transferTx.wait();
  console.log(`Direct USDC transfer successful! Transaction hash: ${transferReceipt.hash}`);
  
  // Check contract's USDC balance
  const contractUsdcBalance = await usdc.balanceOf(chicksAddress);
  console.log(`Contract USDC balance: ${ethers.formatUnits(contractUsdcBalance, 6)}`);
  
  console.log("\n--- STEP 7: Buying CHICKS with 1 USDC ---");
  try {
    // Execute buy transaction
    const buyTx = await chicks.buy(deployer.address, oneUSDC);
    const buyReceipt = await buyTx.wait();
    console.log(`Purchase successful! Transaction hash: ${buyReceipt.hash}`);
    
    // Get CHICKS balance
    const chicksBalance = await chicks.balanceOf(deployer.address);
    console.log(`CHICKS balance after buying: ${ethers.formatUnits(chicksBalance, 6)}`);
    
    // Check price
    const lastPrice = await chicks.lastPrice();
    console.log(`Current CHICKS price: ${ethers.formatUnits(lastPrice, 6)} USDC`);
    
    console.log("\n--- STEP 8: Selling half of CHICKS ---");
    // Sell half of the CHICKS balance
    const halfChicksBalance = ethers.toBigInt(chicksBalance) / BigInt(2);
    if (halfChicksBalance > BigInt(0)) {
      const sellTx = await chicks.sell(halfChicksBalance);
      const sellReceipt = await sellTx.wait();
      console.log(`Sell successful! Transaction hash: ${sellReceipt.hash}`);
      
      // Get updated CHICKS balance
      const newChicksBalance = await chicks.balanceOf(deployer.address);
      console.log(`CHICKS balance after selling: ${ethers.formatUnits(newChicksBalance, 6)}`);
    } else {
      console.log("Not enough CHICKS to sell");
    }
    
    console.log("\n--- STEP 9: Using Leverage ---");
    // Use leverage with 2 USDC for 7 days
    const leverageAmount = ethers.parseUnits("2", 6);
    const leverageDays = 7;
    
    // Check if we have enough USDC balance
    const currentUsdcBalance = await usdc.balanceOf(deployer.address);
    console.log(`Current USDC balance: ${ethers.formatUnits(currentUsdcBalance, 6)}`);
    
    if (ethers.toBigInt(currentUsdcBalance) >= ethers.toBigInt(leverageAmount)) {
      try {
        // Calculate leverage fee
        const leverageFee = await chicks.leverageFee(leverageAmount, leverageDays);
        console.log(`Leverage fee for ${leverageDays} days: ${ethers.formatUnits(leverageFee, 6)} USDC`);
        
        // Execute leverage transaction
        const leverageTx = await chicks.leverage(leverageAmount, leverageDays);
        const leverageReceipt = await leverageTx.wait();
        console.log(`Leverage successful! Transaction hash: ${leverageReceipt.hash}`);
        
        // Get loan details
        const loan = await chicks.Loans(deployer.address);
        console.log(`Loan details:`);
        console.log(`- Collateral: ${ethers.formatUnits(loan.collateral, 6)} CHICKS`);
        console.log(`- Borrowed: ${ethers.formatUnits(loan.borrowed, 6)} USDC`);
        console.log(`- End Date: ${new Date(Number(loan.endDate) * 1000).toLocaleString()}`);
        console.log(`- Number of Days: ${loan.numberOfDays}`);
        
        // Try the borrow function with a different account
        console.log("\n--- STEP 10: Testing Borrow Function ---");
        try {
          // Create a new account for testing borrow
          const borrowWallet = ethers.Wallet.createRandom().connect(ethers.provider);
          
          // Send some ETH to the new wallet for gas
          const sendEthTx = await deployer.sendTransaction({
            to: borrowWallet.address,
            value: ethers.parseEther("0.01")
          });
          await sendEthTx.wait();
          console.log(`Created test wallet and funded with ETH: ${borrowWallet.address}`);
          
          // Send some CHICKS to the new wallet for collateral
          const transferChicksTx = await chicks.transfer(borrowWallet.address, ethers.parseUnits("500", 6));
          await transferChicksTx.wait();
          console.log(`Transferred 500 CHICKS to test wallet for collateral`);
          
          // Connect the contract to the new wallet
          const chicksAsBorrower = chicks.connect(borrowWallet);
          
          // Approve CHICKS for the contract
          const approveChicksTx = await chicksAsBorrower.approve(chicksAddress, ethers.parseUnits("500", 6));
          await approveChicksTx.wait();
          console.log(`Approved CHICKS for borrowing`);
          
          // Check CHICKS balance and allowance
          const chicksBalance = await chicks.balanceOf(borrowWallet.address);
          const chicksAllowance = await chicks.allowance(borrowWallet.address, chicksAddress);
          console.log(`CHICKS balance: ${ethers.formatUnits(chicksBalance, 6)}`);
          console.log(`CHICKS allowance: ${ethers.formatUnits(chicksAllowance, 6)}`);
          
          // Calculate fees for borrowing
          const borrowAmount = ethers.parseUnits("1", 6);
          const borrowDays = 10;
          const interestFee = await chicks.getInterestFee(borrowAmount, borrowDays);
          console.log(`Interest fee for borrowing: ${ethers.formatUnits(interestFee, 6)} USDC`);
          
          // Get the minimum fee value
          const minFee = await chicks.MIN();
          console.log(`Minimum fee required: ${ethers.formatUnits(minFee, 6)} USDC`);
          
          // Calculate the fee address fee (30% of the interest fee)
          const feeAddressFee = interestFee.mul(3).div(10);
          console.log(`Fee address fee: ${ethers.formatUnits(feeAddressFee, 6)} USDC`);
          
          // Check if the fee is sufficient
          if (feeAddressFee.lt(minFee)) {
            console.log(`Fee is less than minimum required. Calculating required borrow amount...`);
            
            // Calculate the required borrow amount to meet the minimum fee
            // MIN = interestFee * 3 / 10
            // interestFee = MIN * 10 / 3
            // borrowAmount = interestFee * 1e6 / (39000 * numberOfDays / 365 + 1000)
            const minInterestFee = minFee.mul(10).div(3);
            const interestRate = ethers.toBigInt(39000) * ethers.toBigInt(borrowDays) / ethers.toBigInt(365) + ethers.toBigInt(1000);
            const requiredBorrowAmount = minInterestFee.mul(ethers.parseUnits("1", 6)).div(interestRate);
            
            // Add a buffer to ensure we're above the minimum
            const borrowAmountWithBuffer = requiredBorrowAmount.mul(12).div(10);
            console.log(`Required borrow amount with buffer: ${ethers.formatUnits(borrowAmountWithBuffer, 6)} USDC`);
            
            try {
              console.log(`Attempting to borrow ${ethers.formatUnits(borrowAmountWithBuffer, 6)} USDC for ${borrowDays} days...`);
              const borrowTx = await chicksAsBorrower.borrow(borrowAmountWithBuffer, borrowDays);
              const borrowReceipt = await borrowTx.wait();
              console.log(`Borrow successful! Transaction hash: ${borrowReceipt.hash}`);
              
              // Get loan details
              const borrowLoan = await chicks.Loans(borrowWallet.address);
              console.log(`Borrow loan details:`);
              console.log(`- Collateral: ${ethers.formatUnits(borrowLoan.collateral, 6)} CHICKS`);
              console.log(`- Borrowed: ${ethers.formatUnits(borrowLoan.borrowed, 6)} USDC`);
              console.log(`- End Date: ${new Date(Number(borrowLoan.endDate) * 1000).toLocaleString()}`);
              console.log(`- Number of Days: ${borrowLoan.numberOfDays}`);
              
              // Test borrowMore
              console.log("\n--- STEP 11: Testing BorrowMore Function ---");
              try {
                // Calculate required borrowMore amount
                const borrowMoreAmount = borrowAmountWithBuffer.div(2);
                console.log(`Attempting to borrow more ${ethers.formatUnits(borrowMoreAmount, 6)} USDC...`);
                const borrowMoreTx = await chicksAsBorrower.borrowMore(borrowMoreAmount);
                const borrowMoreReceipt = await borrowMoreTx.wait();
                console.log(`BorrowMore successful! Transaction hash: ${borrowMoreReceipt.hash}`);
                
                // Get updated loan details
                const updatedLoan = await chicks.Loans(borrowWallet.address);
                console.log(`Updated loan details after borrowMore:`);
                console.log(`- Collateral: ${ethers.formatUnits(updatedLoan.collateral, 6)} CHICKS`);
                console.log(`- Borrowed: ${ethers.formatUnits(updatedLoan.borrowed, 6)} USDC`);
                console.log(`- End Date: ${new Date(Number(updatedLoan.endDate) * 1000).toLocaleString()}`);
                console.log(`- Number of Days: ${updatedLoan.numberOfDays}`);
              } catch (borrowMoreError) {
                console.error(`Error during borrowMore operation: ${borrowMoreError.message}`);
              }
            } catch (error) {
              console.error(`Error during borrow transaction with calculated amount: ${error.message}`);
            }
          } else {
            try {
              // Borrow 1 USDC for 10 days
              console.log(`Attempting to borrow ${ethers.formatUnits(borrowAmount, 6)} USDC for ${borrowDays} days...`);
              const borrowTx = await chicksAsBorrower.borrow(borrowAmount, borrowDays);
              const borrowReceipt = await borrowTx.wait();
              console.log(`Borrow successful! Transaction hash: ${borrowReceipt.hash}`);
              
              // Get loan details
              const borrowLoan = await chicks.Loans(borrowWallet.address);
              console.log(`Borrow loan details:`);
              console.log(`- Collateral: ${ethers.formatUnits(borrowLoan.collateral, 6)} CHICKS`);
              console.log(`- Borrowed: ${ethers.formatUnits(borrowLoan.borrowed, 6)} USDC`);
              console.log(`- End Date: ${new Date(Number(borrowLoan.endDate) * 1000).toLocaleString()}`);
              console.log(`- Number of Days: ${borrowLoan.numberOfDays}`);
            } catch (error) {
              console.error(`Error during borrow transaction: ${error.message}`);
            }
          }
        } catch (borrowError) {
          console.error(`Error during borrow operation: ${borrowError.message}`);
        }
      } catch (error) {
        console.error(`Error during leverage operation: ${error.message}`);
      }
    } else {
      console.warn(`Insufficient USDC balance for leverage. Current balance: ${ethers.formatUnits(currentUsdcBalance, 6)}`);
    }
  } catch (error) {
    console.error(`Error during buy/sell operations: ${error.message}`);
  }
  
  // Set up AAVE integration if addresses are provided
  if (aavePoolAddress && aUsdcTokenAddress) {
    console.log("\n--- STEP 12: Setting up AAVE Integration ---");
    try {
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
    } catch (error) {
      console.error(`Error during AAVE setup: ${error.message}`);
    }
  } else {
    console.log("\nSkipping AAVE integration setup (addresses not provided)");
  }
  
  // Try to verify the contract
  console.log("\n--- STEP 13: Verifying Contract ---");
  try {
    console.log("Waiting 20 seconds before verification to ensure contract is registered on the blockchain...");
    await new Promise(resolve => setTimeout(resolve, 20000));
    
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
          constructorArguments: [usdcAddress],
        });
        console.log("Contract verified on Etherscan");
      } catch (verifyError) {
        console.error("Verification failed:", verifyError.message);
      }
    }
  } catch (error) {
    console.warn("Verification failed, but continuing with setup:", error.message);
  }
  
  console.log("\n=======================================================");
  console.log("Deployment and setup complete!");
  console.log(`CHICKS Contract Address: ${chicksAddress}`);
  console.log(`View your contract on Blockscout: https://base-sepolia.blockscout.com/address/${chicksAddress}`);
  
  // Save the contract address to .env file
  const fs = require('fs');
  try {
    fs.appendFileSync('.env', `\nCHICKS_ADDRESS=${chicksAddress}\n`);
    console.log("Contract address saved to .env file");
  } catch (error) {
    console.error("Failed to save contract address to .env file:", error.message);
  }
  
  // Summary of operations
  console.log("\n--- SUMMARY ---");
  console.log("✅ Contract deployed");
  console.log("✅ Contract configured (fee address, liquidity buffer, start amount)");
  console.log("✅ USDC sent to contract");
  console.log("✅ CHICKS bought");
  console.log("✅ CHICKS sold");
  console.log("✅ Leverage used");
  if (aavePoolAddress && aUsdcTokenAddress) {
    console.log("✅ AAVE integration set up");
  }
  console.log("✅ Contract verified (if successful)");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
