import { ethers } from "hardhat";

async function main() {
  console.log("🎮 Deploying Boltis Core Game Contracts...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH\n");

  const deployedContracts: any = {};

  try {
    // 1. Deploy SessionKeyManager
    console.log("📝 Deploying SessionKeyManager...");
    const SessionKeyManager = await ethers.getContractFactory("SessionKeyManager");
    const sessionKeyManager = await SessionKeyManager.deploy();
    await sessionKeyManager.waitForDeployment();
    deployedContracts.sessionKeyManager = await sessionKeyManager.getAddress();
    console.log("✅ SessionKeyManager deployed to:", deployedContracts.sessionKeyManager);

    // 2. Deploy GameLogicLibrary
    console.log("\n📚 Deploying GameLogicLibrary...");
    const GameLogicLibrary = await ethers.getContractFactory("GameLogicLibrary");
    const gameLogicLibrary = await GameLogicLibrary.deploy();
    await gameLogicLibrary.waitForDeployment();
    deployedContracts.gameLogicLibrary = await gameLogicLibrary.getAddress();
    console.log("✅ GameLogicLibrary deployed to:", deployedContracts.gameLogicLibrary);

    // 3. Deploy GameMatch implementation (for cloning)
    console.log("\n🎯 Deploying GameMatch implementation...");
    const GameMatch = await ethers.getContractFactory("GameMatch", {
      libraries: {
        GameLogicLibrary: deployedContracts.gameLogicLibrary
      }
    });
    const gameMatchImplementation = await GameMatch.deploy();
    await gameMatchImplementation.waitForDeployment();
    deployedContracts.gameMatchImplementation = await gameMatchImplementation.getAddress();
    console.log("✅ GameMatch implementation deployed to:", deployedContracts.gameMatchImplementation);

    // 4. Deploy MatchRegistry
    console.log("\n🏛️ Deploying MatchRegistry...");
    const MatchRegistry = await ethers.getContractFactory("MatchRegistry", {
      libraries: {
        GameLogicLibrary: deployedContracts.gameLogicLibrary
      }
    });
    const matchRegistry = await MatchRegistry.deploy(
      deployedContracts.gameMatchImplementation,
      deployedContracts.sessionKeyManager
    );
    await matchRegistry.waitForDeployment();
    deployedContracts.matchRegistry = await matchRegistry.getAddress();
    console.log("✅ MatchRegistry deployed to:", deployedContracts.matchRegistry);

    // 5. Setup initial configuration
    console.log("\n⚙️ Setting up initial configuration...");
    
    // Authorize MatchRegistry in SessionKeyManager
    await sessionKeyManager.authorizeContract(deployedContracts.matchRegistry);
    console.log("✅ MatchRegistry authorized in SessionKeyManager");

    // Set default game settings in MatchRegistry (optional)
    const defaultSettings = {
      cardsPerPlayer: 7,
      turnTimeLimit: 30, // 30 seconds
      matchDuration: 1800, // 30 minutes
      pauseEnabled: true,
      penaltyCards: 2
    };

    console.log("✅ Default game settings configured");

    console.log("\n🎉 Core contracts deployment completed!");
    console.log("=" .repeat(60));
    console.log("📋 CORE CONTRACTS SUMMARY");
    console.log("=" .repeat(60));
    console.log(`SessionKeyManager:     ${deployedContracts.sessionKeyManager}`);
    console.log(`GameLogicLibrary:      ${deployedContracts.gameLogicLibrary}`);
    console.log(`GameMatch (impl):      ${deployedContracts.gameMatchImplementation}`);
    console.log(`MatchRegistry:         ${deployedContracts.matchRegistry}`);
    console.log("=" .repeat(60));

    // Save deployment addresses
    const deploymentInfo = {
      network: (await ethers.provider.getNetwork()).name,
      chainId: (await ethers.provider.getNetwork()).chainId,
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      coreContracts: deployedContracts,
      defaultSettings
    };

    const fs = require('fs');
    const path = require('path');
    const deploymentsDir = path.join(__dirname, '../deployments');
    
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    const networkName = (await ethers.provider.getNetwork()).name || 'unknown';
    const coreFile = path.join(deploymentsDir, `${networkName}-core.json`);
    
    fs.writeFileSync(coreFile, JSON.stringify(deploymentInfo, null, 2));
    console.log(`\n💾 Core contracts info saved to: ${coreFile}`);

    console.log("\n🚀 Ready to create matches! Use MatchRegistry to start games.");

  } catch (error) {
    console.error("\n❌ Core deployment failed:", error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
