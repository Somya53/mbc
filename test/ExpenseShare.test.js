const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ExpenseShare", function () {
  let owner, payee, contributor1, contributor2;
  let expenseShare, receiptToken;

  beforeEach(async function () {
    [owner, payee, contributor1, contributor2] = await ethers.getSigners();

    // deploy ReceiptToken for testing
    const ReceiptTokenFactory = await ethers.getContractFactory("ReceiptToken");
    receiptToken = await ReceiptTokenFactory.deploy("ReceiptToken", "RCPT");

    // deploy ExpenseShare with no address (no receipt token initially)
    const ExpenseShareFactory = await ethers.getContractFactory("ExpenseShare");
    expenseShare = await ExpenseShareFactory.deploy(ethers.ZeroAddress); // v6 syntax

  });

  it("should allow owner to set receipt token", async function () {
    await expenseShare.setReceiptToken(receiptToken.target); // .target in v6
    expect(await expenseShare.receiptToken()).to.equal(receiptToken.target);
  });

  it("should create a new bill correctly", async function () {
    const target = ethers.parseEther("1"); // 1 ETH
    const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

    const tx = await expenseShare.createBill(payee.address, target, deadline);
    await tx.wait();

    const bill = await expenseShare.bills(0); // first bill

    expect(bill.creator).to.equal(owner.address);
    expect(bill.payee).to.equal(payee.address);
    expect(bill.target).to.equal(target);
    expect(bill.totalPaid).to.equal(0);
    expect(bill.deadline).to.equal(deadline);
    expect(bill.withdrawn).to.equal(false);
  });

  it("should allow contributions and update totalPaid", async function () {
    const target = ethers.parseEther("1");
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    await expenseShare.createBill(payee.address, target, deadline);

    await expenseShare.connect(contributor1).contribute(0, { value: ethers.parseEther("0.3") });
    await expenseShare.connect(contributor2).contribute(0, { value: ethers.parseEther("0.7") });

    const bill = await expenseShare.bills(0);
    expect(bill.totalPaid).to.equal(ethers.parseEther("1"));
  });

  it("should allow payee to withdraw after fully funded", async function () {
    const target = ethers.parseEther("1");
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    await expenseShare.createBill(payee.address, target, deadline);
    await expenseShare.connect(contributor1).contribute(0, { value: target });

    await expect(expenseShare.connect(payee).withdraw(0))
      .to.emit(expenseShare, "Withdrawn")
      .withArgs(0, payee.address, target);
  });
});
