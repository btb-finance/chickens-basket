const { execSync } = require('child_process');
const path = require('path');

console.log('🐔 Starting CHICKENS BASKET comprehensive deployment script 🧺');
console.log('===========================================================');

try {
  // Run the deploy-and-setup.js script with hardhat
  console.log('Running deployment script on Base Sepolia network...');
  execSync('pnpm hardhat run scripts/deploy-and-setup.js --network baseSepolia', { 
    stdio: 'inherit',
    cwd: path.resolve(__dirname, '..')
  });
  
  console.log('\n✅ All operations completed successfully!');
} catch (error) {
  console.error('\n❌ Error occurred during execution:');
  console.error(error.message);
  process.exit(1);
}
