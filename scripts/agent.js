// Agent automation for ExpenseShare on Base Sepolia
// - Listens for BillCreated/Contributed events
// - Automatically distributes rewards, withdraws funded bills, and issues refunds after deadlines
// - Optional webhook notifications (e.g., Slack) via WEBHOOK_URL

require("dotenv").config();
const { ethers } = require("ethers");
const expenseArtifact = require("../artifacts/contracts/ExpenseShare.sol/ExpenseShare.json");

const {
  BASE_SEPOLIA_RPC_URL,
  EXPENSE_ADDRESS,
  AGENT_PRIVATE_KEY,
  WEBHOOK_URL,
  START_BLOCK,
} = process.env;

if (!BASE_SEPOLIA_RPC_URL) throw new Error("BASE_SEPOLIA_RPC_URL missing");
if (!EXPENSE_ADDRESS) throw new Error("EXPENSE_ADDRESS missing");
if (!AGENT_PRIVATE_KEY) throw new Error("AGENT_PRIVATE_KEY missing");

const provider = new ethers.JsonRpcProvider(BASE_SEPOLIA_RPC_URL);
const wallet = new ethers.Wallet(AGENT_PRIVATE_KEY, provider);
const expense = new ethers.Contract(EXPENSE_ADDRESS, expenseArtifact.abi, wallet);
const iface = new ethers.Interface(expenseArtifact.abi);

const bills = new Map(); // billId (string) -> { contributors: Set<string> }

function notify(message) {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${message}`);
  if (WEBHOOK_URL && typeof fetch === "function") {
    fetch(WEBHOOK_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text: message }),
    }).catch((err) => console.error("webhook failed", err));
  }
}

function ensureBill(billId) {
  const key = billId.toString();
  if (!bills.has(key)) bills.set(key, { contributors: new Set() });
  return bills.get(key);
}

async function fetchLogsChunked(filter, fromBlock, toBlock, chunkSize) {
  const logs = [];
  for (let start = fromBlock; start <= toBlock; start += chunkSize) {
    const end = Math.min(start + chunkSize - 1, toBlock);
    const slice = await provider.getLogs({ ...filter, fromBlock: start, toBlock: end });
    logs.push(...slice);
  }
  return logs;
}

async function seedFromPastEvents() {
  const current = await provider.getBlockNumber();
  // stay within provider limits; if START_BLOCK undefined, only backfill ~200 blocks
  const fromBlock = START_BLOCK ? Number(START_BLOCK) : Math.max(current - 200, 0);
  const chunkSize = 8; // provider allows 10, keep under
  notify(`Seeding from block ${fromBlock} to ${current} (chunk ${chunkSize})`);

  const createdLogs = await fetchLogsChunked(
    {
      address: EXPENSE_ADDRESS,
      topics: [iface.getEvent("BillCreated").topicHash],
    },
    fromBlock,
    current,
    chunkSize
  );
  for (const log of createdLogs) {
    const { billId } = iface.decodeEventLog("BillCreated", log.data, log.topics);
    ensureBill(billId);
  }

  const contributedLogs = await fetchLogsChunked(
    {
      address: EXPENSE_ADDRESS,
      topics: [iface.getEvent("Contributed").topicHash],
    },
    fromBlock,
    current,
    chunkSize
  );
  for (const log of contributedLogs) {
    const { billId, from } = iface.decodeEventLog("Contributed", log.data, log.topics);
    ensureBill(billId).contributors.add(from);
  }

  notify(`Tracked bills: ${Array.from(bills.keys()).join(", ") || "none"}`);
}

async function handleBillCreated(log) {
  const { billId } = iface.decodeEventLog("BillCreated", log.data, log.topics);
  ensureBill(billId);
  notify(`BillCreated #${billId}`);
}

async function handleContributed(log) {
  const { billId, from, amount, totalPaid } = iface.decodeEventLog("Contributed", log.data, log.topics);
  ensureBill(billId).contributors.add(from);
  notify(`Contributed bill ${billId} from ${from} amount ${ethers.formatEther(amount)} (total ${ethers.formatEther(totalPaid)})`);
}

async function maybeDistributeRewards(billId, bill) {
  if (bill.rewardPool === 0n) return false;
  notify(`Distribute rewards for bill ${billId}, pool ${ethers.formatEther(bill.rewardPool)}`);
  const tx = await expense.agentDistributeRewards(billId);
  notify(`distribute tx sent: ${tx.hash}`);
  await tx.wait();
  notify(`distribute confirmed: ${tx.hash}`);
  return true;
}

async function maybeWithdraw(billId, bill) {
  if (bill.withdrawn) return false;
  if (bill.totalPaid < bill.target) return false;
  notify(`Withdraw bill ${billId} to payee ${bill.payee} amount ${ethers.formatEther(bill.totalPaid)}`);
  const tx = await expense.agentWithdraw(billId);
  notify(`withdraw tx sent: ${tx.hash}`);
  await tx.wait();
  notify(`withdraw confirmed: ${tx.hash}`);
  return true;
}

async function maybeRefund(billId, bill, contributors) {
  const now = BigInt(Math.floor(Date.now() / 1000));
  if (bill.withdrawn || bill.totalPaid >= bill.target) return false;
  if (bill.deadline === 0n || now <= bill.deadline) return false;

  let any = false;
  for (const addr of contributors) {
    const contributed = await expense.contributions(billId, addr);
    if (contributed > 0n) {
      notify(`Refund bill ${billId} -> ${addr} amount ${ethers.formatEther(contributed)}`);
      const tx = await expense.agentRefund(billId, addr);
      notify(`refund tx sent: ${tx.hash}`);
      await tx.wait();
      notify(`refund confirmed: ${tx.hash}`);
      any = true;
    }
  }
  return any;
}

async function evaluateBill(billId) {
  const bill = await expense.bills(billId);
  const state = ensureBill(billId);
  // Order matters: distribute rewards before withdrawing, since withdraw zeroes totalPaid
  if (bill.totalPaid >= bill.target && bill.rewardPool > 0n && !bill.withdrawn) {
    await maybeDistributeRewards(billId, bill);
  }
  if (bill.totalPaid >= bill.target && !bill.withdrawn) {
    await maybeWithdraw(billId, bill);
  }
  await maybeRefund(billId, bill, state.contributors);
}

async function loop() {
  try {
    for (const billId of bills.keys()) {
      await evaluateBill(BigInt(billId));
    }
  } catch (err) {
    notify(`loop error: ${err}`);
  } finally {
    setTimeout(loop, 30_000);
  }
}

async function main() {
  notify(`Agent starting as ${wallet.address}`);
  const isAgent = await expense.agents(wallet.address);
  if (!isAgent) {
    notify(`WARNING: ${wallet.address} is not added as agent. Owner must call addAgent(${wallet.address}).`);
  }

  await seedFromPastEvents();

  expense.on(expense.filters.BillCreated(), (billId, creator, payee, target, deadline) => {
    ensureBill(billId);
    notify(`(live) BillCreated #${billId} creator ${creator} payee ${payee} target ${ethers.formatEther(target)} deadline ${deadline}`);
  });

  expense.on(expense.filters.Contributed(), (billId, from, amount, totalPaid) => {
    ensureBill(billId).contributors.add(from);
    notify(`(live) Contributed bill ${billId} from ${from} amount ${ethers.formatEther(amount)} total ${ethers.formatEther(totalPaid)}`);
  });

  loop();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
