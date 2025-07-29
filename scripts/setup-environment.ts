import { ethers } from "hardhat";
import * as fs from 'fs';
import * as path from 'path';

async function main() {
  console.log("🛠️ Setting up Boltis development environment...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Setting up with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH\n");

  const networkName = (await ethers.provider.getNetwork()).name || 'unknown';
  const deploymentFile = path.join(__dirname, '../deployments', `${networkName}-deployment.json`);

  if (!fs.existsSync(deploymentFile)) {
    console.error(`❌ Deployment file not found: ${deploymentFile}`);
    console.log("Please run deployment script first: yarn hardhat run scripts/deploy.ts");
    process.exit(1);
  }

  const deploymentInfo = JSON.parse(fs.readFileSync(deploymentFile, 'utf8'));
  const contracts = deploymentInfo.contracts;

  try {
    console.log("🎮 Setting up game environment...");

    // Get contract instances
    const sessionKeyManager = await ethers.getContractAt("SessionKeyManager", contracts.SessionKeyManager);
    const matchRegistry = await ethers.getContractAt("MatchRegistry", contracts.MatchRegistry);
    const mockUSDC = await ethers.getContractAt("MockUSDC", contracts.MockUSDC);
    const mockUSDT = await ethers.getContractAt("MockUSDT", contracts.MockUSDT);
    const mockBoltisToken = await ethers.getContractAt("MockBoltisToken", contracts.MockBoltisToken);

    // 1. Setup session key for deployer
    console.log("\n🔑 Setting up session key for deployer...");
    const sessionKeyAddress = ethers.Wallet.createRandom().address;
    
    try {
      await sessionKeyManager.createSessionKey(
        sessionKeyAddress,
        ethers.parseEther("0.1"), // 0.1 ETH daily gas limit
        [contracts.MatchRegistry] // Authorized contracts
      );
      console.log("✅ Session key created:", sessionKeyAddress);
    } catch (error: any) {
      if (error.message.includes("Session key already exists")) {
        console.log("✅ Session key already exists for this user");
      } else {
        throw error;
      }
    }

    // 2. Mint test tokens to deployer
    console.log("\n💰 Minting test tokens...");
    
    // Mint USDC
    await mockUSDC.faucet(ethers.parseUnits("10000", 6)); // 10,000 USDC
    const usdcBalance = await mockUSDC.balanceOf(deployer.address);
    console.log(`✅ USDC balance: ${ethers.formatUnits(usdcBalance, 6)} USDC`);

    // Mint USDT
    await mockUSDT.faucet(ethers.parseUnits("10000", 6)); // 10,000 USDT
    const usdtBalance = await mockUSDT.balanceOf(deployer.address);
    console.log(`✅ USDT balance: ${ethers.formatUnits(usdtBalance, 6)} USDT`);

    // Mint BOLTIS
    await mockBoltisToken.faucet(ethers.parseUnits("1000", 18)); // 1,000 BOLTIS
    const boltisBalance = await mockBoltisToken.balanceOf(deployer.address);
    console.log(`✅ BOLTIS balance: ${ethers.formatUnits(boltisBalance, 18)} BOLTIS`);

    // 3. Create a test match (optional)
    console.log("\n🎯 Creating test match...");
    
    const gameSettings = {
      cardsPerPlayer: 7,
      turnTimeLimit: 60, // 1 minute
      matchDuration: 1800, // 30 minutes
      pauseEnabled: true,
      penaltyCards: 2
    };

    const testPlayers = [
      deployer.address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address
    ];

    try {
      const tx = await matchRegistry.createMatch(
        testPlayers,
        gameSettings,
        ethers.parseEther("0.01"), // 0.01 ETH stake
        { value: ethers.parseEther("0.01") }
      );
      const receipt = await tx.wait();
      
      // Get match ID from events
      const matchCreatedEvent = receipt?.logs.find((log: any) => {
        try {
          const parsed = matchRegistry.interface.parseLog(log);
          return parsed?.name === 'MatchCreated';
        } catch {
          return false;
        }
      });

      if (matchCreatedEvent) {
        const parsedEvent = matchRegistry.interface.parseLog(matchCreatedEvent);
        const matchId = parsedEvent?.args[0];
        console.log(`✅ Test match created with ID: ${matchId}`);
      } else {
        console.log("✅ Test match created (ID not found in events)");
      }
    } catch (error: any) {
      console.log("⚠️ Test match creation failed (this is optional):", error.message);
    }

    // 4. Generate environment config file
    console.log("\n📄 Generating environment config...");
    
    const envConfig = {
      network: networkName,
      chainId: Number((await ethers.provider.getNetwork()).chainId),
      rpcUrl: ethers.provider._getConnection().url,
      contracts: {
        SessionKeyManager: contracts.SessionKeyManager,
        MatchRegistry: contracts.MatchRegistry,
        GameMatchImplementation: contracts.GameMatchImplementation,
        GameLogicLibrary: contracts.GameLogicLibrary,
        MockUSDC: contracts.MockUSDC,
        MockUSDT: contracts.MockUSDT,
        MockBoltisToken: contracts.MockBoltisToken
      },
      testAccounts: {
        deployer: deployer.address,
        sessionKey: sessionKeyAddress
      },
      gameSettings: gameSettings
    };

    const configFile = path.join(__dirname, '../deployments', `${networkName}-config.json`);
    fs.writeFileSync(configFile, JSON.stringify(envConfig, null, 2));
    console.log(`✅ Environment config saved to: ${configFile}`);

    console.log("\n🎉 Environment setup completed!");
    console.log("=" .repeat(60));
    console.log("📋 DEVELOPMENT ENVIRONMENT READY");
    console.log("=" .repeat(60));
    console.log(`Network:           ${networkName}`);
    console.log(`Chain ID:          ${envConfig.chainId}`);
    console.log(`Deployer:          ${deployer.address}`);
    console.log(`Session Key:       ${sessionKeyAddress}`);
    console.log(`USDC Balance:      ${ethers.formatUnits(usdcBalance, 6)} USDC`);
    console.log(`USDT Balance:      ${ethers.formatUnits(usdtBalance, 6)} USDT`);
    console.log(`BOLTIS Balance:    ${ethers.formatUnits(boltisBalance, 18)} BOLTIS`);
    console.log("=" .repeat(60));
    console.log("\n🚀 Ready to start developing and testing!");
    console.log("💡 Use the config file for frontend integration");

  } catch (error) {
    console.error("\n❌ Environment setup failed:", error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
