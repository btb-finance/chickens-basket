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
  - `buy.js`: Script for purchasing CHICKS tokens with USDC
  - `setupAave.js`: Script for configuring AAVE integration
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
pnpm hardhat node
```

2. In a new terminal, deploy to local network:
```bash
pnpm hardhat run scripts/deploy.js --network localhost
```

### Base Sepolia Testnet Deployment

1. Ensure your `.env` file is properly configured with all required values:

```env
# Network Configuration
rpc_url="https://sepolia.base.org"  # Base Sepolia RPC URL
private_key="YOUR_PRIVATE_KEY"      # Wallet private key
chain_id=84532                      # Base Sepolia chain ID

# Contract Configuration
usdc_address="0x..."                # USDC token contract address on Base Sepolia
aave_pool_address="0x..."           # AAVE pool address on Base Sepolia
ausdc_token_address="0x..."         # aUSDC token address on Base Sepolia
min_liquidity_buffer="1000000"      # Min USDC buffer (in wei)
fee_address="0x..."                 # Fee recipient address
set_start="1000000"                 # Initial contract amount

# API Keys
ethscan_api_key="YOUR_ETHERSCAN_API_KEY" # For contract verification
```

2. Deploy to Base Sepolia network:
```bash
pnpm hardhat run scripts/deploy.js --network base
```

3. For a comprehensive deployment and setup in one step, use the deploy-and-setup.js script:
```bash
pnpm hardhat run scripts/deploy-and-setup.js --network base
```

This script will:
1. Deploy the CHICKS contract
2. Verify the contract on Blockscout
3. Set the minimum liquidity buffer
4. Set the fee address
5. Set the start amount
6. Send 1 USDC to the contract
7. Approve USDC spending
8. Buy 1 USDC worth of CHICKS tokens
9. Set up AAVE integration (pool address, aToken address, and enable AAVE)
10. Buy 10 USDC worth of CHICKS tokens

### Contract Verification

The deployment script automatically verifies the contract on Blockscout for Base Sepolia. The verification process uses Sourcify for Blockscout compatibility.

## GitHub Workflow

### Creating and Pushing to a New Branch

1. Ensure you have Git installed and configured on your machine.

2. Initialize Git repository (if not already done):
```bash
git init
```

3. Add your files to the staging area:
```bash
git add .
```

4. Commit your changes:
```bash
git commit -m "Initial commit with CHICKS contract implementation"
```

5. Create a new branch for your feature or changes:
```bash
git checkout -b feature/base-sepolia-deployment
```

6. Make your changes and commit them:
```bash
git add .
git commit -m "Deploy CHICKS contract to Base Sepolia"
```

7. If the repository already exists on GitHub, add it as a remote:
```bash
git remote add origin https://github.com/yourusername/chickens-basket.git
```

8. Push your branch to GitHub:
```bash
git push -u origin feature/base-sepolia-deployment
```

9. Create a Pull Request on GitHub to merge your changes into the main branch.

### Best Practices for Branch Management

- Use descriptive branch names with prefixes like `feature/`, `bugfix/`, or `deployment/`
- Keep branches focused on a single task or feature
- Regularly pull changes from the main branch to stay up-to-date
- Delete branches after they've been merged

## Using the Scripts

### Buy CHICKS Tokens

The `buy.js` script allows you to purchase CHICKS tokens using USDC:

```bash
node scripts/buy.js <receiver-address> <usdc-amount>
```

Parameters:
- `<receiver-address>`: Ethereum address that will receive the CHICKS tokens
- `<usdc-amount>`: Amount of USDC to spend (in decimal format, e.g., 100.5)

Required Environment Variables:
- `CHICKS_ADDRESS`: Address of the deployed CHICKS contract
- `USDC_ADDRESS`: Address of the USDC token contract
- `rpc_url`: RPC endpoint for the network
- `private_key`: Private key of the wallet executing the purchase

The script will:
1. Validate the receiver address and USDC amount
2. Check your USDC balance
3. Approve USDC spending if needed
4. Execute the purchase transaction
5. Display the transaction details and updated CHICKS balance

### Setup AAVE Integration

The `setupAave.js` script configures the AAVE protocol integration for yield generation:

```bash
node scripts/setupAave.js
```

Required Environment Variables:
- `CHICKS_ADDRESS`: Address of the deployed CHICKS contract
- `aave_pool_address`: Address of the AAVE lending pool
- `ausdc_token_address`: Address of the aUSDC token
- `rpc_url`: RPC endpoint for the network
- `private_key`: Private key of the wallet with owner permissions

The script will:
1. Set the aUSDC token address in the CHICKS contract
2. Configure the AAVE pool address
3. Enable AAVE integration functionality

This setup allows the contract to deposit excess USDC into AAVE for yield generation while maintaining the required liquidity buffer.

## License

This project is licensed under the BUSL-1.1 License.