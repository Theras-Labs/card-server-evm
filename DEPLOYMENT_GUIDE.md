# Boltis Contracts - Testnet Deployment Guide

This guide will help you deploy the Boltis smart contracts to Sepolia and Hyperion testnets.

## 🔧 Prerequisites

1. **Node.js and Yarn**: Ensure you have Node.js and Yarn installed
2. **Testnet ETH/tMETIS**: You'll need test tokens for both networks
3. **Private Key**: Your wallet's private key for deployment
4. **API Keys**: For contract verification (optional but recommended)

## 🌐 Supported Networks

### Sepolia Testnet (Ethereum)

- **Chain ID**: 11155111
- **Currency**: SepoliaETH
- **RPC**: `https://sepolia.infura.io/v3/YOUR_INFURA_PROJECT_ID`
- **Explorer**: https://sepolia.etherscan.io
- **Faucet**: https://sepoliafaucet.com

### Hyperion Testnet (Metis)

- **Chain ID**: 133717
- **Currency**: tMETIS
- **RPC**: `https://hyperion-testnet.metisdevops.link`
- **Explorer**: https://hyperion-testnet-explorer.metisdevops.link
- **Faucet**: https://faucet.metis.io

## 📋 Step-by-Step Deployment

### Step 1: Environment Setup

1. **Create .env file** in the project root:

   ```bash
   cp .env.example .env
   ```

2. **Fill in your .env file**:

   ```env
   # Your wallet private key (without 0x prefix)
   PRIVATE_KEY=your_actual_private_key_here

   # RPC URLs
   SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_PROJECT_ID
   HYPERION_RPC_URL=https://hyperion-testnet.metisdevops.link

   # API Keys for verification (optional)
   ETHERSCAN_API_KEY=your_etherscan_api_key
   HYPERION_API_KEY=your_hyperion_api_key

   # Infura Project ID (for Sepolia)
   INFURA_PROJECT_ID=your_infura_project_id
   ```

3. **Get Test Tokens**:
   - **Sepolia**: Get SepoliaETH from https://sepoliafaucet.com
   - **Hyperion**: Get tMETIS from https://faucet.metis.io

### Step 2: Install Dependencies

```bash
yarn install
```

### Step 3: Compile Contracts

```bash
yarn compile
```

### Step 4: Deploy to Networks

#### Deploy to Sepolia Testnet

```bash
# Full deployment (all contracts)
yarn deploy:sepolia

# Or deploy step by step
yarn deploy:core:sepolia      # Core game contracts only
yarn deploy:tokens:sepolia    # Mock ERC20 tokens only
```

#### Deploy to Hyperion Testnet

```bash
# Full deployment (all contracts)
yarn deploy:hyperion

# Or deploy step by step
yarn deploy:core:hyperion     # Core game contracts only
yarn deploy:tokens:hyperion   # Mock ERC20 tokens only
```

### Step 5: Verify Contracts (Optional)

After deployment, verify your contracts on the block explorers:

```bash
# Verify on Sepolia
yarn verify:sepolia

# Verify on Hyperion
yarn verify:hyperion
```

### Step 6: Setup Development Environment

Set up test data and configuration:

```bash
# Setup Sepolia environment
yarn setup:sepolia

# Setup Hyperion environment
yarn setup:hyperion
```

## 📁 Deployment Output

After successful deployment, you'll find deployment information in the `deployments/` directory:

```
deployments/
├── sepolia-deployment.json     # Full Sepolia deployment info
├── sepolia-core.json          # Core contracts only
├── sepolia-tokens.json        # Mock tokens only
├── sepolia-config.json        # Environment config
├── hyperion-deployment.json   # Full Hyperion deployment info
├── hyperion-core.json         # Core contracts only
├── hyperion-tokens.json       # Mock tokens only
└── hyperion-config.json       # Environment config
```

## 🔍 Troubleshooting

### Common Issues

1. **Insufficient Gas**:

   ```
   Error: insufficient funds for gas * price + value
   ```

   **Solution**: Get more test tokens from the faucets

2. **Network Connection Issues**:

   ```
   Error: could not detect network
   ```

   **Solution**: Check your RPC URLs in .env file

3. **Private Key Issues**:

   ```
   Error: invalid private key
   ```

   **Solution**: Ensure private key is correct (without 0x prefix)

4. **Library Linking Issues**:
   ```
   Error: library not found
   ```
   **Solution**: This is handled automatically by our deployment scripts

### Gas Estimation

Approximate gas costs for full deployment:

- **Sepolia**: ~0.02 ETH
- **Hyperion**: ~0.02 tMETIS

## 🎯 Post-Deployment Testing

After deployment, you can test your contracts:

1. **Check deployment files** in `deployments/` directory
2. **Verify contracts** on block explorers
3. **Test mock token faucets**:
   ```bash
   # The setup script will mint test tokens to your address
   yarn setup:sepolia    # or yarn setup:hyperion
   ```

## 🔐 Security Notes

- ⚠️ **Never commit your .env file** to version control
- ⚠️ **Use separate keys** for testnet and mainnet
- ⚠️ **Keep your private keys secure**
- ✅ The .env file is already in .gitignore

## 📞 Support

If you encounter issues:

1. Check the console output for detailed error messages
2. Verify your .env configuration
3. Ensure you have sufficient test tokens
4. Check network status on the respective explorers

## 🚀 Next Steps

After successful deployment:

1. Save the contract addresses from deployment files
2. Update your frontend/backend with the new addresses
3. Test the game functionality
4. Consider setting up monitoring for your contracts

---

**Happy Deploying! 🎮**
