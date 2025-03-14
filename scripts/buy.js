const { ethers } = require("ethers");
require("dotenv").config();
const fs = require("fs");

// ABI imports
const IERC20_ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)"
];

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
  
  // Fallback to minimal ABI
  return [
    "function buy(address receiver, uint256 usdcAmount) returns (uint256)",
    "function getBuyChicks(uint256 usdcAmount) view returns (uint256)",
    "function balanceOf(address owner) view returns (uint256)"
  ];
}

async function main() {
    // Set the default amount to 1 USDC
    const amountInUSD = "1";
    
    // Get the receiver address from command line arguments or use the sender address
    const args = process.argv.slice(2);
    const receiverAddress = args.length > 0 && ethers.isAddress(args[0]) 
        ? args[0] 
        : null; // Will use signer address if null

    // Validate and convert USDC amount
    const amountInUSDC = ethers.parseUnits(amountInUSD, 6); // USDC has 6 decimals

    // Get the deployed contract addresses
    const chicksAddress = process.env.CHICKS_ADDRESS || "0xb3F89f7F5e0240323B92Fd95ffC5d5a5EaabEAe9";
    const usdcAddress = process.env.usdc_address;

    if (!usdcAddress) {
        throw new Error("Please set usdc_address in your .env file");
    }

    // Set up provider and signer
    const provider = new ethers.JsonRpcProvider(process.env.rpc_url);
    const signer = new ethers.Wallet(process.env.private_key, provider);
    const signerAddress = await signer.getAddress();
    console.log("Using account:", signerAddress);

    // Use signer address as receiver if not provided
    const finalReceiverAddress = receiverAddress || signerAddress;
    console.log("Receiver address:", finalReceiverAddress);

    // Get contract instances
    const chicksAbi = getChicksAbi();
    const chicks = new ethers.Contract(chicksAddress, chicksAbi, signer);
    const usdc = new ethers.Contract(usdcAddress, IERC20_ABI, signer);

    // Check USDC balance
    const usdcBalance = await usdc.balanceOf(signerAddress);
    console.log(`Current USDC balance: ${ethers.formatUnits(usdcBalance, 6)}`);
    
    if (usdcBalance < amountInUSDC * 2n) { // Need at least 2 USDC (1 for direct transfer + 1 for buying)
        throw new Error(`Insufficient USDC balance. You have ${ethers.formatUnits(usdcBalance, 6)} USDC but need at least 2 USDC`);
    }

    // STEP 1: First send 1 USDC directly to the contract
    console.log("\n--- STEP 1: Sending 1 USDC directly to the contract ---");
    try {
        const transferTx = await usdc.transfer(chicksAddress, amountInUSDC);
        const transferReceipt = await transferTx.wait();
        console.log(`Direct USDC transfer successful! Transaction hash: ${transferReceipt.hash}`);
    } catch (error) {
        console.error("Error transferring USDC directly:", error.message);
        throw error;
    }

    // STEP 2: Approve USDC for the buy function
    console.log("\n--- STEP 2: Approving USDC for the buy function ---");
    try {
        const allowance = await usdc.allowance(signerAddress, chicksAddress);
        console.log(`Current USDC allowance: ${ethers.formatUnits(allowance, 6)}`);
        
        if (allowance < amountInUSDC) {
            console.log("Approving USDC spend...");
            const approveTx = await usdc.approve(chicksAddress, ethers.parseUnits("1000000", 6));
            await approveTx.wait();
            console.log("USDC approved successfully");
        } else {
            console.log("USDC already approved, skipping approval");
        }
    } catch (error) {
        console.error("Error approving USDC:", error.message);
        throw error;
    }

    // STEP 3: Buy CHICKS tokens with 1 USDC
    console.log("\n--- STEP 3: Buying CHICKS tokens with 1 USDC ---");
    try {
        // Get expected CHICKS tokens
        const expectedChicks = await chicks.getBuyChicks(amountInUSDC);
        console.log(`Expected CHICKS tokens: ${ethers.formatEther(expectedChicks)}`);

        // Execute buy transaction
        console.log("Buying CHICKS tokens...");
        const buyTx = await chicks.buy(finalReceiverAddress, amountInUSDC);
        const receipt = await buyTx.wait();

        console.log("Purchase successful!");
        console.log(`Transaction hash: ${receipt.hash}`);
        
        // Get updated CHICKS balance
        const chicksBalance = await chicks.balanceOf(finalReceiverAddress);
        console.log(`New CHICKS balance: ${ethers.formatEther(chicksBalance)}`);
    } catch (error) {
        console.error("Error buying CHICKS tokens:", error.message);
        throw error;
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });