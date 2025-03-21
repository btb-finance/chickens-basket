require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 2000
      }
    }
  },
  networks: {
    hardhat: {},
    sepolia: {
      url: process.env.rpc_url || "https://eth-sepolia.g.alchemy.com/v2/demo",
      accounts: process.env.private_key ? [process.env.private_key] : [],
      chainId: process.env.chain_id ? parseInt(process.env.chain_id) : 11155111
    },
    base: {
      url: process.env.base_rpc_url || "https://mainnet.base.org",
      accounts: process.env.private_key ? [process.env.private_key] : [],
      chainId: 8453
    },
    baseSepolia: {
      url: process.env.base_sepolia_rpc_url || "https://sepolia.base.org",
      accounts: process.env.private_key ? [process.env.private_key] : [],
      chainId: 84532
    }
  },
  etherscan: {
    apiKey: {
      base: process.env.ethscan_api_key || "",
      baseSepolia: process.env.ethscan_api_key || ""
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org"
        }
      },
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://base-sepolia.blockscout.com/api",
          browserURL: "https://base-sepolia.blockscout.com"
        }
      }
    ]
  },
  sourcify: {
    enabled: true
  }
};