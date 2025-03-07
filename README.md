# USDCtoCHICKS Smart Contract Project

A smart contract project for managing USDC to CHICKS token conversion with integrated AAVE functionality.

## Prerequisites

- Node.js (v14 or later)
- npm or yarn package manager
- An Ethereum wallet (e.g., MetaMask)
- Infura or Alchemy API key for deployment

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd chickens-basket
```

2. Install dependencies:
```bash
npm install
```

3. Configure environment variables:
   - Copy `.env.example` to `.env`
   - Fill in the required values:

```env
# Network Configuration
rpc_url="YOUR_RPC_URL"         # Infura/Alchemy endpoint
private_key="YOUR_PRIVATE_KEY" # Wallet private key
chain_id=11155111              # Network chain ID (e.g., 11155111 for Sepolia)

# Contract Configuration
usdc_address="YOUR_USDC_ADDRESS"      # USDC token contract address
fee_address="YOUR_FEE_ADDRESS"        # Fee recipient address
min_liquidity_buffer="1000000000"     # Min USDC buffer (in wei)
set_start="true"                      # Initial contract state

# API Keys
ethscan_api_key="YOUR_ETHERSCAN_API_KEY" # For contract verification
```

## Project Structure

- `contracts/`: Smart contract source files
  - `chicks.sol`: Main CHICKS token contract implementation
- `scripts/`: Deployment and interaction scripts
  - `deploy.js`: Contract deployment script
- `test/`: Test files for contract verification
- `hardhat.config.js`: Hardhat configuration file

## Features

- ERC20 compliant token implementation
- AAVE protocol integration for yield generation
- Secure token basket management
- Configurable fees and liquidity parameters
- Automated contract verification
- Comprehensive testing suite

## Deployment

### Local Development

1. Start a local Hardhat node:
```bash
npx hardhat node
```

2. In a new terminal, deploy to local network:
```bash
npx hardhat run scripts/deploy.js --network localhost
```

### Testnet/Mainnet Deployment

1. Ensure your `.env` file is properly configured with all required values.

2. Deploy to your chosen network:
```bash
npx hardhat run scripts/deploy.js --network <network-name>
```
Replace `<network-name>` with the desired network (e.g., sepolia, mainnet).

## Contract Verification

The deployment script automatically verifies the contract on Etherscan for non-local networks. Ensure you have set the correct `ethscan_api_key` in your `.env` file.

## Security

- The contract includes reentrancy protection
- Uses OpenZeppelin's secure contract implementations
- Implements two-step ownership transfer
- Features configurable liquidity buffers

## License

This project is licensed under the BUSL-1.1 License.