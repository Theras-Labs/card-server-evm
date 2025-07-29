import { ethers, upgrades } from "hardhat";
import { Contract } from "ethers";

interface DeployedContracts {
  sessionKeyManager: Contract;
  gameLogicLibrary: Contract;
  gameMatchImplementation: Contract;
  matchRegistry: Contract;
  mockUSDC: Contract;
  mockUSDT: Contract;
  mockBoltisToken: Contract;
}

async function main() {
  console.log("🚀 Starting Boltis contracts deployment...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH\n");

  const deployedContracts: Partial<DeployedContracts> = {};

  try {
    // 1. Deploy SessionKeyManager
    console.log("📝 Deploying SessionKeyManager...");
    const SessionKeyManager = await ethers.getContractFactory("SessionKeyManager");
    const sessionKeyManager = await SessionKeyManager.deploy();
    await sessionKeyManager.waitForDeployment();
    deployedContracts.sessionKeyManager = sessionKeyManager;
    console.log("✅ SessionKeyManager deployed to:", await sessionKeyManager.getAddress());

    // 2. Deploy GameLogicLibrary
    console.log("\n📚 Deploying GameLogicLibrary...");
    const GameLogicLibrary = await ethers.getContractFactory("GameLogicLibrary");
    const gameLogicLibrary = await GameLogicLibrary.deploy();
    await gameLogicLibrary.waitForDeployment();
    deployedContracts.gameLogicLibrary = gameLogicLibrary;
    console.log("✅ GameLogicLibrary deployed to:", await gameLogicLibrary.getAddress());

    // 3. Deploy GameMatch implementation (for cloning)
    console.log("\n🎮 Deploying GameMatch implementation...");
    const GameMatch = await ethers.getContractFactory("GameMatch", {
      libraries: {
        GameLogicLibrary: await gameLogicLibrary.getAddress()
      }
    });
    const gameMatchImplementation = await GameMatch.deploy();
    await gameMatchImplementation.waitForDeployment();
    deployedContracts.gameMatchImplementation = gameMatchImplementation;
    console.log("✅ GameMatch implementation deployed to:", await gameMatchImplementation.getAddress());

    // 4. Deploy MatchRegistry
    console.log("\n🏛️ Deploying MatchRegistry...");
    const MatchRegistry = await ethers.getContractFactory("MatchRegistry", {
      libraries: {
        GameLogicLibrary: await gameLogicLibrary.getAddress()
      }
    });
    const matchRegistry = await MatchRegistry.deploy(
      await gameMatchImplementation.getAddress(),
      await sessionKeyManager.getAddress()
    );
    await matchRegistry.waitForDeployment();
    deployedContracts.matchRegistry = matchRegistry;
    console.log("✅ MatchRegistry deployed to:", await matchRegistry.getAddress());

    // 5. Deploy Mock ERC20 Tokens
    console.log("\n💰 Deploying Mock ERC20 Tokens...");
    
    // Deploy MockUSDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy();
    await mockUSDC.waitForDeployment();
    deployedContracts.mockUSDC = mockUSDC;
    console.log("✅ MockUSDC deployed to:", await mockUSDC.getAddress());

    // Deploy MockUSDT
    const MockUSDT = await ethers.getContractFactory("MockUSDT");
    const mockUSDT = await MockUSDT.deploy();
    await mockUSDT.waitForDeployment();
    deployedContracts.mockUSDT = mockUSDT;
    console.log("✅ MockUSDT deployed to:", await mockUSDT.getAddress());

    // Deploy MockBoltisToken
    const MockBoltisToken = await ethers.getContractFactory("MockBoltisToken");
    const mockBoltisToken = await MockBoltisToken.deploy();
    await mockBoltisToken.waitForDeployment();
    deployedContracts.mockBoltisToken = mockBoltisToken;
    console.log("✅ MockBoltisToken deployed to:", await mockBoltisToken.getAddress());

    // 6. Setup initial configuration
    console.log("\n⚙️ Setting up initial configuration...");
    
    // Authorize MatchRegistry in SessionKeyManager
    await sessionKeyManager.authorizeContract(await matchRegistry.getAddress());
    console.log("✅ MatchRegistry authorized in SessionKeyManager");

    // Print deployment summary
    console.log("\n🎉 Deployment completed successfully!");
    console.log("=" .repeat(60));
    console.log("📋 DEPLOYMENT SUMMARY");
    console.log("=" .repeat(60));
    console.log(`SessionKeyManager:     ${await deployedContracts.sessionKeyManager!.getAddress()}`);
    console.log(`GameLogicLibrary:      ${await deployedContracts.gameLogicLibrary!.getAddress()}`);
    console.log(`GameMatch (impl):      ${await deployedContracts.gameMatchImplementation!.getAddress()}`);
    console.log(`MatchRegistry:         ${await deployedContracts.matchRegistry!.getAddress()}`);
    console.log(`MockUSDC:              ${await deployedContracts.mockUSDC!.getAddress()}`);
    console.log(`MockUSDT:              ${await deployedContracts.mockUSDT!.getAddress()}`);
    console.log(`MockBoltisToken:       ${await deployedContracts.mockBoltisToken!.getAddress()}`);
    console.log("=" .repeat(60));

    // Save deployment addresses to file
    const deploymentInfo = {
      network: (await ethers.provider.getNetwork()).name,
      chainId: (await ethers.provider.getNetwork()).chainId,
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      contracts: {
        SessionKeyManager: await deployedContracts.sessionKeyManager!.getAddress(),
        GameLogicLibrary: await deployedContracts.gameLogicLibrary!.getAddress(),
        GameMatchImplementation: await deployedContracts.gameMatchImplementation!.getAddress(),
        MatchRegistry: await deployedContracts.matchRegistry!.getAddress(),
        MockUSDC: await deployedContracts.mockUSDC!.getAddress(),
        MockUSDT: await deployedContracts.mockUSDT!.getAddress(),
        MockBoltisToken: await deployedContracts.mockBoltisToken!.getAddress()
      }
    };

    const fs = require('fs');
    const path = require('path');
    const deploymentsDir = path.join(__dirname, '../deployments');
    
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    const networkName = (await ethers.provider.getNetwork()).name || 'unknown';
    const deploymentFile = path.join(deploymentsDir, `${networkName}-deployment.json`);
    
    fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
    console.log(`\n💾 Deployment info saved to: ${deploymentFile}`);

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
