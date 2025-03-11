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
    sepolia: {
      url: process.env.rpc_url,
      accounts: [process.env.private_key],
      chainId: parseInt(process.env.chain_id)
    }
  },
  etherscan: {
    apiKey: process.env.ethscan_api_key
  }
};