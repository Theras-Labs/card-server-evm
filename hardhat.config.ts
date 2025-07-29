import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "paris",
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    sepolia: {
      url:
        process.env.SEPOLIA_RPC_URL ||
        `https://sepolia.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111,
      gasPrice: parseInt(process.env.GAS_PRICE || "20000000000"),
      gas: parseInt(process.env.GAS_LIMIT || "8000000"),
    },
    hyperion: {
      url:
        process.env.HYPERION_RPC_URL ||
        "https://hyperion-testnet.metisdevops.link",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 133717,
      gasPrice: parseInt(process.env.GAS_PRICE || "20000000000"),
      gas: parseInt(process.env.GAS_LIMIT || "8000000"),
    },
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      hyperion: process.env.HYPERION_API_KEY || "",
    },
    customChains: [
      {
        network: "hyperion",
        chainId: 133717,
        urls: {
          apiURL: "https://hyperion-testnet-explorer.metisdevops.link/api",
          browserURL: "https://hyperion-testnet-explorer.metisdevops.link",
        },
      },
    ],
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },
};

export default config;
