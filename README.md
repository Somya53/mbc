# Boiler-Blockchain-Project

Collaborative expense sharing on Ethereum/Base: create bills with targets, contributors send ETH, receipt tokens mint/burn on contribution/refund, payees withdraw when funded, owner can seed/distribute rewards. An optional agent automates withdrawals/refunds/rewards.

## Table of Contents
- [Setup](#setup)
- [Local Run](#local-run)
- [Deploy](#deploy)
- [Deterministic Deploy](#deterministic-deploy-same-address-every-time)
- [Agent Automation](#agent-automation-base-sepolia)
- [Architecture Overview](#architecture-overview)

## Setup
Create `.env` in repo root:
```
SEPOLIA_RPC_URL=<ethereum-sepolia-rpc>
BASE_SEPOLIA_RPC_URL=<base-sepolia-rpc>
PRIVATE_KEY=0x<owner/deployer key>
EXPENSE_ADDRESS=0x<current ExpenseShare address>        # for agent/frontend
AGENT_PRIVATE_KEY=0x<agent wallet; must be added by owner>
WEBHOOK_URL=<optional slack/webhook endpoint>
START_BLOCK=<optional backfill start block for agent>
```
Install deps: `npm install`

## Local Run
- Frontend: `python3 -m http.server 8080 --directory frontend` then open http://127.0.0.1:8080
- Hardhat console (Base Sepolia): `npx hardhat console --network baseSepolia`

## Deploy
- Ethereum Sepolia: `npx hardhat run scripts/deploy.js --network sepolia`
- Base Sepolia: `npx hardhat run scripts/deploy.js --network baseSepolia`

## Deterministic deploy (same address every time)
- Uses the EIP-2470 CREATE2 factory (`0x0000000000FFe8B47B3e2130213B802212439497`).
- Script: `npx hardhat run scripts/deploy_create2.js --network baseSepolia`
- Fixed salts:
  - ReceiptToken salt: `ethers.id("expense-receipt-v1")`
  - ExpenseShare salt: `ethers.id("expense-share-v1")`
- Derived addresses stay stable as long as bytecode/constructor args stay the same; script skips redeploy if already present and rewires minter.

## Agent automation (Base Sepolia)
`scripts/agent.js` auto-distributes rewards, withdraws funded bills, and refunds expired unfunded bills via the agent role.

Setup:
1) Owner calls `addAgent(<agent address>)` on ExpenseShare.
2) Run: `node scripts/agent.js`

Behavior:
- Tracks `BillCreated`/`Contributed` events.
- If funded and reward pool > 0, calls `agentDistributeRewards` before `agentWithdraw`.
- If past deadline and unfunded, calls `agentRefund` for contributors with balances.
- Logs to console; posts `{ text: "<message>" }` to `WEBHOOK_URL` if set.

## Architecture Overview
- Contracts:
  - `ExpenseShare`: bills (creator/payee/target/deadline/totalPaid/rewardPool/withdrawn), contribute with optional receipt tokens, withdraw (payee), refund (after deadline if unfunded), reward pool seed/distribute, agent role for automated actions.
  - `ReceiptToken`: ERC-20 with `setMinter`, `mint`, `burn` used as contribution receipts.
- Frontend (`frontend/index.html`): vanilla JS + ethers v6 UMD; connects wallet, allows create/contribute/withdraw/refund, inspects bills, pulls token info, and logs contract events (including agent-driven).
- Agent (`scripts/agent.js`): Node script using `AGENT_PRIVATE_KEY`; backfills events (configurable `START_BLOCK`), watches live events, triggers agent calls in order: distributeRewards → withdraw → refund after deadline; optional webhook notifications; chunked log queries to respect RPC limits.
