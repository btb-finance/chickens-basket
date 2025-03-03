# EggsToChicks Smart Contract Project

A decentralized finance (DeFi) project that implements a token basket system using smart contracts on the Ethereum blockchain. This project is part of the BTB Finance ecosystem.

## Overview

EggsToChicks is a smart contract system that allows users to interact with token baskets in a decentralized manner. The project implements ERC20 standards and includes features for token management and basket operations.

## Prerequisites

- Node.js (v14 or later)
- npm or yarn package manager
- An Ethereum wallet (e.g., MetaMask)
- Infura API key for deployment

## Installation

1. Clone the repository:
```bash
git clone https://github.com/btb-finance/chickens-basket.git
cd chickens-basket
```

2. Install dependencies:
```bash
npm install
```

## Testing

Run the comprehensive test suite to ensure all components are working as expected:

```bash
npm test
# or
npx hardhat test
```

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

1. Create a `.env` file in the root directory with your configuration:
```env
PRIVATE_KEY=your_wallet_private_key
INFURA_API_KEY=your_infura_api_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

2. Deploy to your chosen network:
```bash
npx hardhat run scripts/deploy.js --network <network-name>
```
Replace `<network-name>` with the desired network (e.g., sepolia, mainnet).

## Project Structure

- `contracts/`: Smart contract source files
  - `chicks.sol`: Main contract implementation
- `test/`: Test files for contract verification
- `scripts/`: Deployment and interaction scripts
- `hardhat.config.js`: Hardhat configuration file

## Features

- ERC20 compliant token implementation
- Secure token basket management
- Automated testing suite
- Flexible deployment options
- OpenZeppelin contract integration

## Security

- All contracts use the latest version of Solidity (^0.8.20)
- Implements OpenZeppelin's secure contract standards
- Comprehensive test coverage

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

ISC

## Support

For support and inquiries, please open an issue in the GitHub repository.