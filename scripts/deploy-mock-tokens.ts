import { ethers } from "hardhat";

async function main() {
  console.log("🪙 Deploying Mock ERC20 Tokens...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH\n");

  const deployedTokens: any = {};

  try {
    // Deploy MockUSDC
    console.log("💵 Deploying MockUSDC...");
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy();
    await mockUSDC.waitForDeployment();
    deployedTokens.mockUSDC = await mockUSDC.getAddress();
    console.log("✅ MockUSDC deployed to:", deployedTokens.mockUSDC);

    // Deploy MockUSDT
    console.log("\n💵 Deploying MockUSDT...");
    const MockUSDT = await ethers.getContractFactory("MockUSDT");
    const mockUSDT = await MockUSDT.deploy();
    await mockUSDT.waitForDeployment();
    deployedTokens.mockUSDT = await mockUSDT.getAddress();
    console.log("✅ MockUSDT deployed to:", deployedTokens.mockUSDT);

    // Deploy MockBoltisToken
    console.log("\n🎮 Deploying MockBoltisToken...");
    const MockBoltisToken = await ethers.getContractFactory("MockBoltisToken");
    const mockBoltisToken = await MockBoltisToken.deploy();
    await mockBoltisToken.waitForDeployment();
    deployedTokens.mockBoltisToken = await mockBoltisToken.getAddress();
    console.log("✅ MockBoltisToken deployed to:", deployedTokens.mockBoltisToken);

    // Test faucet functions
    console.log("\n🚰 Testing faucet functions...");
    
    // Test USDC faucet
    await mockUSDC.faucet(ethers.parseUnits("100", 6)); // 100 USDC
    const usdcBalance = await mockUSDC.balanceOf(deployer.address);
    console.log(`✅ USDC faucet test: ${ethers.formatUnits(usdcBalance, 6)} USDC received`);

    // Test USDT faucet
    await mockUSDT.faucet(ethers.parseUnits("100", 6)); // 100 USDT
    const usdtBalance = await mockUSDT.balanceOf(deployer.address);
    console.log(`✅ USDT faucet test: ${ethers.formatUnits(usdtBalance, 6)} USDT received`);

    // Test BOLTIS faucet
    await mockBoltisToken.faucet(ethers.parseUnits("50", 18)); // 50 BOLTIS
    const boltisBalance = await mockBoltisToken.balanceOf(deployer.address);
    console.log(`✅ BOLTIS faucet test: ${ethers.formatUnits(boltisBalance, 18)} BOLTIS received`);

    console.log("\n🎉 Mock tokens deployment completed!");
    console.log("=" .repeat(50));
    console.log("📋 MOCK TOKENS SUMMARY");
    console.log("=" .repeat(50));
    console.log(`MockUSDC:        ${deployedTokens.mockUSDC}`);
    console.log(`MockUSDT:        ${deployedTokens.mockUSDT}`);
    console.log(`MockBoltisToken: ${deployedTokens.mockBoltisToken}`);
    console.log("=" .repeat(50));

    // Save token addresses
    const tokenInfo = {
      network: (await ethers.provider.getNetwork()).name,
      chainId: (await ethers.provider.getNetwork()).chainId,
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      tokens: deployedTokens
    };

    const fs = require('fs');
    const path = require('path');
    const deploymentsDir = path.join(__dirname, '../deployments');
    
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    const networkName = (await ethers.provider.getNetwork()).name || 'unknown';
    const tokenFile = path.join(deploymentsDir, `${networkName}-tokens.json`);
    
    fs.writeFileSync(tokenFile, JSON.stringify(tokenInfo, null, 2));
    console.log(`\n💾 Token addresses saved to: ${tokenFile}`);

  } catch (error) {
    console.error("\n❌ Token deployment failed:", error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
