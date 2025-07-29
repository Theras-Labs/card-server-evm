import { ethers, run } from "hardhat";
import * as fs from 'fs';
import * as path from 'path';

interface DeploymentInfo {
  contracts: {
    [key: string]: string;
  };
}

async function main() {
  console.log("🔍 Starting contract verification...\n");

  const networkName = (await ethers.provider.getNetwork()).name || 'unknown';
  const deploymentFile = path.join(__dirname, '../deployments', `${networkName}-deployment.json`);

  if (!fs.existsSync(deploymentFile)) {
    console.error(`❌ Deployment file not found: ${deploymentFile}`);
    console.log("Please run deployment script first.");
    process.exit(1);
  }

  const deploymentInfo: DeploymentInfo = JSON.parse(fs.readFileSync(deploymentFile, 'utf8'));
  const contracts = deploymentInfo.contracts;

  console.log(`📋 Found deployment info for network: ${networkName}`);
  console.log(`🔗 Verifying ${Object.keys(contracts).length} contracts...\n`);

  const verificationResults: { [key: string]: boolean } = {};

  try {
    // Verify SessionKeyManager
    console.log("🔍 Verifying SessionKeyManager...");
    try {
      await run("verify:verify", {
        address: contracts.SessionKeyManager,
        constructorArguments: []
      });
      verificationResults.SessionKeyManager = true;
      console.log("✅ SessionKeyManager verified");
    } catch (error: any) {
      if (error.message.includes("Already Verified")) {
        console.log("✅ SessionKeyManager already verified");
        verificationResults.SessionKeyManager = true;
      } else {
        console.log("❌ SessionKeyManager verification failed:", error.message);
        verificationResults.SessionKeyManager = false;
      }
    }

    // Verify GameLogicLibrary
    console.log("\n🔍 Verifying GameLogicLibrary...");
    try {
      await run("verify:verify", {
        address: contracts.GameLogicLibrary,
        constructorArguments: []
      });
      verificationResults.GameLogicLibrary = true;
      console.log("✅ GameLogicLibrary verified");
    } catch (error: any) {
      if (error.message.includes("Already Verified")) {
        console.log("✅ GameLogicLibrary already verified");
        verificationResults.GameLogicLibrary = true;
      } else {
        console.log("❌ GameLogicLibrary verification failed:", error.message);
        verificationResults.GameLogicLibrary = false;
      }
    }

    // Verify GameMatch Implementation
    console.log("\n🔍 Verifying GameMatch Implementation...");
    try {
      await run("verify:verify", {
        address: contracts.GameMatchImplementation,
        constructorArguments: [],
        libraries: {
          GameLogicLibrary: contracts.GameLogicLibrary
        }
      });
      verificationResults.GameMatchImplementation = true;
      console.log("✅ GameMatch Implementation verified");
    } catch (error: any) {
      if (error.message.includes("Already Verified")) {
        console.log("✅ GameMatch Implementation already verified");
        verificationResults.GameMatchImplementation = true;
      } else {
        console.log("❌ GameMatch Implementation verification failed:", error.message);
        verificationResults.GameMatchImplementation = false;
      }
    }

    // Verify MatchRegistry
    console.log("\n🔍 Verifying MatchRegistry...");
    try {
      await run("verify:verify", {
        address: contracts.MatchRegistry,
        constructorArguments: [
          contracts.GameMatchImplementation,
          contracts.SessionKeyManager
        ],
        libraries: {
          GameLogicLibrary: contracts.GameLogicLibrary
        }
      });
      verificationResults.MatchRegistry = true;
      console.log("✅ MatchRegistry verified");
    } catch (error: any) {
      if (error.message.includes("Already Verified")) {
        console.log("✅ MatchRegistry already verified");
        verificationResults.MatchRegistry = true;
      } else {
        console.log("❌ MatchRegistry verification failed:", error.message);
        verificationResults.MatchRegistry = false;
      }
    }

    // Verify Mock Tokens
    const mockTokens = ['MockUSDC', 'MockUSDT', 'MockBoltisToken'];
    
    for (const tokenName of mockTokens) {
      if (contracts[tokenName]) {
        console.log(`\n🔍 Verifying ${tokenName}...`);
        try {
          await run("verify:verify", {
            address: contracts[tokenName],
            constructorArguments: []
          });
          verificationResults[tokenName] = true;
          console.log(`✅ ${tokenName} verified`);
        } catch (error: any) {
          if (error.message.includes("Already Verified")) {
            console.log(`✅ ${tokenName} already verified`);
            verificationResults[tokenName] = true;
          } else {
            console.log(`❌ ${tokenName} verification failed:`, error.message);
            verificationResults[tokenName] = false;
          }
        }
      }
    }

    // Summary
    console.log("\n🎉 Verification process completed!");
    console.log("=" .repeat(50));
    console.log("📋 VERIFICATION SUMMARY");
    console.log("=" .repeat(50));
    
    let successCount = 0;
    const totalCount = Object.keys(verificationResults).length;
    
    for (const [contractName, success] of Object.entries(verificationResults)) {
      const status = success ? "✅ VERIFIED" : "❌ FAILED";
      console.log(`${contractName.padEnd(25)} ${status}`);
      if (success) successCount++;
    }
    
    console.log("=" .repeat(50));
    console.log(`📊 Success Rate: ${successCount}/${totalCount} (${Math.round(successCount/totalCount*100)}%)`);
    
    if (successCount === totalCount) {
      console.log("🎉 All contracts verified successfully!");
    } else {
      console.log("⚠️  Some contracts failed verification. Check the logs above for details.");
    }

  } catch (error) {
    console.error("\n❌ Verification process failed:", error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
