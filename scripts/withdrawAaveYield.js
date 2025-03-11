const { ethers } = require("ethers");
const dotenv = require("dotenv");
const fs = require("fs");

dotenv.config();

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
  
  // Fallback to minimal ABI with the AAVE yield functions
  return [
    "function withdrawAaveYield(address _to, uint256 _principalAmount, uint256 _withdrawAmount) external",
    "function getAaveSuppliedAmount() view returns (uint256)"
  ];
}

async function main() {
    try {
        // Get command line arguments
        const args = process.argv.slice(2);
        if (args.length !== 3) {
            throw new Error("Please provide recipient address, principal amount, and withdrawal amount as arguments");
        }

        const [recipientAddress, principalAmount, withdrawAmount] = args;

        // Validate recipient address
        if (!ethers.isAddress(recipientAddress)) {
            throw new Error("Invalid recipient address");
        }

        // Validate amounts
        if (isNaN(principalAmount) || Number(principalAmount) < 0) {
            throw new Error("Principal amount must be a non-negative number");
        }

        if (isNaN(withdrawAmount) || Number(withdrawAmount) < 0) {
            throw new Error("Withdrawal amount must be a non-negative number");
        }

        // Convert amounts to wei
        const principalAmountWei = ethers.parseUnits(principalAmount.toString(), 6); // USDC has 6 decimals
        const withdrawAmountWei = ethers.parseUnits(withdrawAmount.toString(), 6);

        // Get the contract address from environment variables
        const CHICKS_ADDRESS = process.env.CHICKS_ADDRESS;
        if (!CHICKS_ADDRESS) {
            throw new Error("CHICKS_ADDRESS not set in environment variables");
        }

        // Connect to the network
        const provider = new ethers.JsonRpcProvider(process.env.rpc_url);
        const signer = new ethers.Wallet(process.env.private_key, provider);
        console.log("Using account:", signer.address);

        // Get contract instance
        const chicksAbi = getChicksAbi();
        const chicksContract = new ethers.Contract(
            CHICKS_ADDRESS,
            chicksAbi,
            signer
        );

        console.log(`Withdrawing AAVE yield to ${recipientAddress}...`);
        console.log(`Principal amount: ${principalAmount} USDC`);
        console.log(`Withdrawal amount: ${withdrawAmount === '0' ? 'ALL AVAILABLE' : withdrawAmount + ' USDC'}`);

        // Call the withdrawAaveYield function with the required parameters
        const tx = await chicksContract.withdrawAaveYield(recipientAddress, principalAmountWei, withdrawAmountWei);
        console.log("Transaction hash:", tx.hash);

        // Wait for transaction confirmation
        const receipt = await tx.wait();
        console.log("Transaction confirmed in block:", receipt.blockNumber);

        // Get updated AAVE supply amount
        const aaveSupply = await chicksContract.getAaveSuppliedAmount();
        console.log("Current AAVE supply:", ethers.formatUnits(aaveSupply, 6), "USDC");

        console.log("Successfully withdrew AAVE yield");
    } catch (error) {
        console.error("Error withdrawing AAVE yield:", error.message);
        process.exit(1);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });