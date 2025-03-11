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
    }
  },
  etherscan: {
    apiKey: process.env.ethscan_api_key || ""
  }
};