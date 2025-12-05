// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// simple contract to share expenses
// people can chip in ETH to a target, and once it's full, the payee can grab it
// optionally, contributors can get receipt tokens if configured
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ReceiptToken.sol";

contract ExpenseShare is ReentrancyGuard, Ownable {
    // ----------------------------
    // structs & storage
    // ----------------------------
    struct Bill {
        address creator;       // who made the bill
        address payable payee; // who can withdraw after funded
        uint256 target;        // total amount wanted in wei
        uint256 totalPaid;     // total added so far
        uint256 deadline;      // unix time for refund (0 = no deadline)
        bool withdrawn;        // has payee taken the money yet
        uint256 rewardPool;    // extra pool for contributors (optional)
    }

    uint256 public nextBillId; // keeps track of bill ids
    mapping(uint256 => Bill) public bills; // billId => bill
    mapping(uint256 => mapping(address => uint256)) public contributions; // billId => contributor => amount
    ReceiptToken public receiptToken; // optional receipt token
    uint256 public tokenUnit = 1e15; // how many tokens per wei unit, e.g. 0.001 ETH => 1 token

    // events
    event BillCreated(uint256 indexed billId, address indexed creator, address indexed payee, uint256 target, uint256 deadline);
    event Contributed(uint256 indexed billId, address indexed from, uint256 amount, uint256 totalPaid);
    event Withdrawn(uint256 indexed billId, address indexed payee, uint256 amount);
    event Refunded(uint256 indexed billId, address indexed contributor, uint256 amount);
    event RewardPaid(uint256 indexed billId, address indexed contributor, uint256 reward);

    // simple custom errors
    error BillNotFound();
    error AlreadyWithdrawn();
    error NotPayee();
    error NotFunded();
    error DeadlineNotPassed();
    error NoContribution();

    // ----------------------------
    // constructor / admin stuff
    // ----------------------------
    constructor(address _receiptToken) {
        if (_receiptToken != address(0)) {
            receiptToken = ReceiptToken(_receiptToken);
        }
    }

    // owner can swap receipt token later
    function setReceiptToken(address token) external onlyOwner {
        receiptToken = ReceiptToken(token);
    }

    // set how many tokens per wei
    function setTokenUnit(uint256 _tokenUnit) external onlyOwner {
        require(_tokenUnit > 0, "tokenUnit must be > 0");
        tokenUnit = _tokenUnit;
    }

    // ----------------------------
    // bill lifecycle
    // ----------------------------
    // make a new bill
    function createBill(address payable payee, uint256 targetWei, uint256 deadlineUnix) external returns (uint256) {
        require(payee != address(0), "invalid payee");
        require(targetWei > 0, "target must be > 0");

        uint256 billId = nextBillId++;
        bills[billId] = Bill({
            creator: msg.sender,
            payee: payee,
            target: targetWei,
            totalPaid: 0,
            deadline: deadlineUnix,
            withdrawn: false,
            rewardPool: 0
        });

        emit BillCreated(billId, msg.sender, payee, targetWei, deadlineUnix);
        return billId;
    }

    // chip in ETH to a bill
    function contribute(uint256 billId) external payable nonReentrant {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        require(msg.value > 0, "no eth sent");
        require(!b.withdrawn, "bill already withdrawn");

        uint256 remaining = (b.totalPaid >= b.target) ? 0 : (b.target - b.totalPaid);

        uint256 accepted = msg.value;
        uint256 surplus = 0;

        if (remaining == 0) {
            // already funded, refund all
            surplus = msg.value;
            accepted = 0;
        } else if (msg.value > remaining) {
            // accept only what's needed
            accepted = remaining;
            surplus = msg.value - remaining;
        }

        if (accepted > 0) {
            contributions[billId][msg.sender] += accepted;
            b.totalPaid += accepted;
            emit Contributed(billId, msg.sender, accepted, b.totalPaid);

            // mint receipt tokens if we have the contract set
            if (address(receiptToken) != address(0)) {
                uint256 tokenAmount = accepted / tokenUnit;
                if (tokenAmount > 0) {
                    receiptToken.mint(msg.sender, tokenAmount);
                }
            }
        }

        if (surplus > 0) {
            // refund extra
            (bool refunded, ) = payable(msg.sender).call{value: surplus}("");
            require(refunded, "refund failed");
        }
    }

    // check if a bill is fully funded
    function isFunded(uint256 billId) public view returns (bool) {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        return b.totalPaid >= b.target;
    }

    // payee takes the money
    function withdraw(uint256 billId) external nonReentrant {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        if (b.withdrawn) revert AlreadyWithdrawn();
        if (msg.sender != b.payee) revert NotPayee();
        if (b.totalPaid < b.target) revert NotFunded();

        b.withdrawn = true;
        uint256 amount = b.totalPaid;
        b.totalPaid = 0;

        (bool sent, ) = b.payee.call{value: amount}("");
        require(sent, "withdraw failed");

        emit Withdrawn(billId, b.payee, amount);
    }

    // refund if deadline passed and bill not funded
    function refund(uint256 billId) external nonReentrant {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        if (b.withdrawn) revert AlreadyWithdrawn();
        if (b.deadline == 0 || block.timestamp <= b.deadline) revert DeadlineNotPassed();
        if (b.totalPaid >= b.target) revert NotFunded();

        uint256 contributed = contributions[billId][msg.sender];
        if (contributed == 0) revert NoContribution();

        contributions[billId][msg.sender] = 0;
        b.totalPaid -= contributed;

        // burn receipt tokens if needed
        if (address(receiptToken) != address(0)) {
            uint256 tokenAmount = contributed / tokenUnit;
            if (tokenAmount > 0) {
                receiptToken.burn(msg.sender, tokenAmount);
            }
        }

        (bool ok, ) = payable(msg.sender).call{value: contributed}("");
        require(ok, "refund transfer failed");

        emit Refunded(billId, msg.sender, contributed);
    }

    // ----------------------------
    // simple rewards
    // ----------------------------
    // owner can add extra rewards to a bill
    function seedRewardPool(uint256 billId) external payable onlyOwner {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        require(msg.value > 0, "no value");
        b.rewardPool += msg.value;
    }

    // distribute reward pool after bill funded
    function distributeRewards(uint256 billId) external nonReentrant {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        if (b.totalPaid < b.target) revert NotFunded();
        uint256 pool = b.rewardPool;
        require(pool > 0, "no reward pool");

        b.rewardPool = 0;

        // simple version: send whole pool to owner
        (bool ok, ) = payable(owner()).call{value: pool}("");
        require(ok, "reward transfer failed");
    }

    // ----------------------------
    // view helpers
    // ----------------------------
    function contributorAmount(uint256 billId, address contributor) external view returns (uint256) {
        return contributions[billId][contributor];
    }

    // rescue accidentally sent ETH
    function rescueETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "rescue failed");
    }

    // prevent random ETH sends
    receive() external payable {
        revert("Use contribute(billId)");
    }

    fallback() external payable {
        revert("Use contribute(billId)");
    }
}
