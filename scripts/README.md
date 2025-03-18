# CHICKS Token Deployment Scripts

This directory contains scripts for deploying and interacting with the CHICKS token contract.

## Available Scripts

### `deploy.js`
Basic deployment script that only deploys the contract and sets up initial configuration.

### `deploy-and-setup.js`
Comprehensive script that:
- Deploys the CHICKS contract
- Sets up the contract (fee address, liquidity buffer, start amount)
- Sends USDC to the contract
- Buys CHICKS tokens
- Sells CHICKS tokens
- Uses leverage functionality
- Tests borrow functionality with a separate test wallet
- Tests borrowMore functionality to increase an existing loan
- Sets up AAVE integration (if addresses are provided)
- Verifies the contract on Blockscout

### `run-all.js`
A simple wrapper script that runs `deploy-and-setup.js` on the Base Sepolia network.

## Loan Functions

The script demonstrates three different ways to interact with the CHICKS contract for loans:

1. **Leverage**: The user provides a fee and receives both CHICKS tokens as collateral and USDC as a loan. The contract mints CHICKS tokens directly to the user.

2. **Borrow**: The user provides existing CHICKS tokens as collateral and receives USDC as a loan. The contract transfers the CHICKS tokens from the user to itself.

3. **BorrowMore**: The user increases an existing loan by borrowing more USDC against their existing collateral or by providing additional collateral.

Each function has different parameters and behaviors:
- **Leverage**: `leverage(uint256 usdc, uint256 numberOfDays)` - The user specifies how much USDC they want to leverage and for how many days.
- **Borrow**: `borrow(uint256 usdc, uint256 numberOfDays)` - The user specifies how much USDC they want to borrow and for how many days.
- **BorrowMore**: `borrowMore(uint256 usdc)` - The user specifies how much additional USDC they want to borrow against their existing loan.

## How to Use

### One-Command Deployment and Setup
To deploy and set up everything in one command, run:

```bash
pnpm node scripts/run-all.js
```

This will execute the entire deployment and setup process on the Base Sepolia network.

### Custom Deployment
To deploy to a specific network with custom parameters, run:

```bash
pnpm hardhat run scripts/deploy-and-setup.js --network <network-name>
```

## Environment Variables

The scripts use the following environment variables (with defaults for testing):

- `usdc_address`: USDC token address (default: Base Sepolia USDC)
- `fee_address`: Fee recipient address (default: dead address)
- `min_liquidity_buffer`: Minimum liquidity buffer (default: 1 USDC)
- `set_start`: Initial start amount (default: 1 USDC)
- `aave_pool_address`: AAVE pool address (optional)
- `ausdc_token_address`: aUSDC token address (optional)

You can set these variables in your `.env` file.

## Requirements

- Make sure you have USDC tokens in your account before running the scripts
- For Base Sepolia, you can get test USDC from the Base Sepolia Faucet
