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

To start frontend: From repo root run: python3 -m http.server 8080 --directory frontend

## Agent automation (Base Sepolia)

Use `scripts/agent.js` to auto-distribute rewards, withdraw funded bills, and refund expired unfunded bills via the agent role.

Env (add to `.env`):
```
BASE_SEPOLIA_RPC_URL=<base sepolia rpc>
EXPENSE_ADDRESS=0x... (deployed ExpenseShare)
AGENT_PRIVATE_KEY=0x... (agent wallet; must be added by owner)
WEBHOOK_URL=<optional slack/webhook endpoint>
START_BLOCK=<optional block to backfill contributions>
```

Setup:
1) Owner calls `addAgent(<agent address>)` on ExpenseShare.
2) Run the agent: `node scripts/agent.js`

Behavior:
- Listens for `BillCreated` and `Contributed` events to track contributors.
- If a bill is funded and has a reward pool, it calls `agentDistributeRewards` before `agentWithdraw`.
- If past deadline and not funded, it calls `agentRefund` for contributors with balances.
- Logs to console; sends webhook JSON `{ text: "<message>" }` when `WEBHOOK_URL` is set.
