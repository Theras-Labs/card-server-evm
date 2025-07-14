import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import "@openzeppelin/hardhat-upgrades";
// require('@nomiclabs/hardhat-ethers');
// require('@openzeppelin/hardhat-upgrades');
import dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          evmVersion: "paris",
        },
      },
    ],
  },
  networks: {
    hyperion: {
      chainId: 133717,
      url: "hyperion-testnet.metisdevops.link",
      accounts:
        process.env.ACCOUNT_KEY !== undefined ? [process.env.ACCOUNT_KEY] : [],
      // 1001
    },
  },
};

export default config;
