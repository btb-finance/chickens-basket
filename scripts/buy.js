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
    // Get command line arguments
    const args = process.argv.slice(2);
    if (args.length !== 2) {
        throw new Error("Please provide receiver address and USDC amount as arguments");
    }

    const [receiverAddress, amountInUSD] = args;

    // Validate receiver address
    if (!ethers.isAddress(receiverAddress)) {
        throw new Error("Invalid receiver address");
    }

    // Validate and convert USDC amount
    if (isNaN(amountInUSD) || Number(amountInUSD) <= 0) {
        throw new Error("USDC amount must be a positive number");
    }
    const amountInUSDC = ethers.parseUnits(amountInUSD.toString(), 6);

    // Get the deployed contract addresses from environment variables
    const chicksAddress = process.env.CHICKS_ADDRESS;
    const usdcAddress = process.env.USDC_ADDRESS;

    if (!chicksAddress || !usdcAddress) {
        throw new Error("Please set CHICKS_ADDRESS and USDC_ADDRESS in your .env file");
    }

    // Set up provider and signer
    const provider = new ethers.JsonRpcProvider(process.env.rpc_url);
    const signer = new ethers.Wallet(process.env.private_key, provider);
    console.log("Using account:", signer.address);

    // Get contract instances
    const chicksAbi = getChicksAbi();
    const chicks = new ethers.Contract(chicksAddress, chicksAbi, signer);
    const usdc = new ethers.Contract(usdcAddress, IERC20_ABI, signer);

    // Check USDC balance
    const usdcBalance = await usdc.balanceOf(signer.address);
    if (usdcBalance < amountInUSDC) {
        throw new Error(`Insufficient USDC balance. You have ${ethers.formatUnits(usdcBalance, 6)} USDC`);
    }

    // Check allowance and approve if needed
    const allowance = await usdc.allowance(signer.address, chicksAddress);
    console.log(`Current USDC allowance: ${ethers.formatUnits(allowance, 6)}`);
    
    // Always approve a large amount to ensure sufficient allowance
    console.log("Approving USDC spend...");
    try {
        const approveTx = await usdc.approve(chicksAddress, ethers.parseUnits("1000000", 6));
        await approveTx.wait();
        console.log("USDC approved successfully");
    } catch (error) {
        console.error("Error approving USDC:", error.message);
        throw error;
    }

    // Get expected CHICKS tokens
    const expectedChicks = await chicks.getBuyChicks(amountInUSDC);
    console.log(`Expected CHICKS tokens: ${ethers.formatEther(expectedChicks)}`);

    // Execute buy transaction
    console.log("Buying CHICKS tokens...");
    const buyTx = await chicks.buy(receiverAddress, amountInUSDC);
    const receipt = await buyTx.wait();

    console.log("Purchase successful!");
    console.log(`Transaction hash: ${receipt.transactionHash}`);
    
    // Get updated CHICKS balance
    const chicksBalance = await chicks.balanceOf(signer.address);
    console.log(`New CHICKS balance: ${ethers.formatEther(chicksBalance)}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });