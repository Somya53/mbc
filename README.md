# Boiler-Blockchain-Project

Collaborative expense sharing on Base: create bills with targets, contributors send ETH, receipt tokens mint/burn on contribution/refund, payees withdraw when funded, owner can seed/distribute rewards.

## Table of Contents
- [Setup](#setup)
- [Local Run](#local-run)
- [Deploy](#deploy)
- [Architecture Overview](#architecture-overview)

## Setup
Create `.env` in repo root:
```
SEPOLIA_RPC_URL=<ethereum-sepolia-rpc>
BASE_SEPOLIA_RPC_URL=<base-sepolia-rpc>
PRIVATE_KEY=0x<owner/deployer key>
EXPENSE_ADDRESS=0x<current ExpenseShare address>        # for frontend
```
Install deps: `npm install`

## Local Run
- Frontend: `python3 -m http.server 8080 --directory frontend` then open http://127.0.0.1:8080
- Hardhat console (Base Sepolia): `npx hardhat console --network baseSepolia`

## Deploy
- Base Sepolia: `npx hardhat run scripts/deploy.js --network baseSepolia`

## Architecture Overview
- Contracts:
  - `ExpenseShare`: bills (creator/payee/target/deadline/totalPaid/rewardPool/withdrawn), contribute with optional receipt tokens, withdraw (payee), refund (after deadline if unfunded), reward pool seed/distribute.
  - `ReceiptToken`: ERC-20 with `setMinter`, `mint`, `burn` used as contribution receipts.
- Frontend (`frontend/index.html`): vanilla JS + ethers v6 UMD; connects wallet, allows create/contribute/withdraw/refund, inspects bills, pulls token info, and logs contract events.
