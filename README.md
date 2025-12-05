# Boiler-Blockchain-Project

We chose the Open Track and implemented a custom smart contract that enables collaborative expense sharing on Ethereum. Users can create shared expense bills with a funding target, and contributors can send ETH toward that target. The contract optionally issues ERC-20 “receipt tokens” to contributors and allows contributors to reclaim funds if a deadline passes without reaching the goal. Once a bill is fully funded, the designated payee can securely withdraw the collected amount. Additionally, the system includes an optional reward pool that the contract owner can seed and distribute, which further motivates participation.

# To Run

Set environment (add to `.env`):
```
SEPOLIA_RPC_URL=<ethereum-sepolia-rpc>
BASE_SEPOLIA_RPC_URL=<base-sepolia-rpc>
PRIVATE_KEY=0x<private-key>
```

Deploy:
- Ethereum Sepolia: `npx hardhat run scripts/deploy.js --network sepolia`
- Base Sepolia: `npx hardhat run scripts/deploy.js --network baseSepolia`

To start frontend: npx http-server frontend
