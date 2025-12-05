const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // Deploy ReceiptToken
  const ReceiptToken = await ethers.getContractFactory("ReceiptToken", deployer);
  const receiptToken = await ReceiptToken.deploy("Receipt Token", "RCT");
  await receiptToken.waitForDeployment();
  const receiptAddr = await receiptToken.getAddress();
  console.log("ReceiptToken deployed at:", receiptAddr);

  // Deploy ExpenseShare
  const ExpenseShare = await ethers.getContractFactory("ExpenseShare", deployer);
  const expenseShare = await ExpenseShare.deploy(receiptAddr);
  await expenseShare.waitForDeployment();
  const expenseAddr = await expenseShare.getAddress();
  console.log("ExpenseShare deployed at:", expenseAddr);

  // Set ExpenseShare as minter
  console.log("Setting minter on ReceiptToken to", expenseAddr);
  const tx = await receiptToken.connect(deployer).setMinter(expenseAddr);
  console.log("  tx:", tx.hash);
  await tx.wait();
  console.log("Minter set to:", expenseAddr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
