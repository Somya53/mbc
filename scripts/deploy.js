async function main() {
  //Deploy ReceiptToken
  const ReceiptToken = await ethers.getContractFactory("ReceiptToken");
  const receiptToken = await ReceiptToken.deploy("Receipt Token", "RCT");
  await receiptToken.waitForDeployment();

  console.log("ReceiptToken deployed at:", await receiptToken.getAddress());

  //Deploy ExpenseShare
  const ExpenseShare = await ethers.getContractFactory("ExpenseShare");
  const expenseShare = await ExpenseShare.deploy(await receiptToken.getAddress());
  await expenseShare.waitForDeployment();

  console.log("ExpenseShare deployed at:", await expenseShare.getAddress());

  //Set ExpenseShare as minter
  const tx = await receiptToken.setMinter(await expenseShare.getAddress());
  await tx.wait();

  console.log("Minter set to:", await expenseShare.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
