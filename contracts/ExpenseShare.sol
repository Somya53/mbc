// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ReceiptToken.sol";

/// @title ExpenseShare with Agent Automation
/// @notice Users contribute to bills, payees can withdraw, agent handles automated actions
contract ExpenseShare is ReentrancyGuard, Ownable {
    struct Bill {
        address creator;
        address payable payee;
        uint256 target;
        uint256 totalPaid;
        uint256 deadline;
        bool withdrawn;
        uint256 rewardPool;
    }

    uint256 public nextBillId;
    mapping(uint256 => Bill) public bills;
    mapping(uint256 => mapping(address => uint256)) public contributions;

    ReceiptToken public receiptToken;
    uint256 public tokenUnit = 1e15;

    mapping(address => bool) public agents;

    // ----------------------------
    // Events
    // ----------------------------
    event BillCreated(uint256 indexed billId, address indexed creator, address indexed payee, uint256 target, uint256 deadline);
    event Contributed(uint256 indexed billId, address indexed from, uint256 amount, uint256 totalPaid);
    event Withdrawn(uint256 indexed billId, address indexed payee, uint256 amount);
    event Refunded(uint256 indexed billId, address indexed contributor, uint256 amount);
    event RewardPaid(uint256 indexed billId, address indexed recipient, uint256 amount);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);

    // ----------------------------
    // Errors
    // ----------------------------
    error BillNotFound();
    error AlreadyWithdrawn();
    error NotPayee();
    error NotFunded();
    error DeadlineNotPassed();
    error NoContribution();
    error NotAgent();

    // ----------------------------
    // Modifiers
    // ----------------------------
    modifier onlyAgent() {
        if (!agents[msg.sender]) revert NotAgent();
        _;
    }

    // ----------------------------
    // Constructor
    // ----------------------------
    constructor(address _receiptToken) {
        if (_receiptToken != address(0)) {
            receiptToken = ReceiptToken(_receiptToken);
        }
    }

    // ----------------------------
    // Agent Management
    // ----------------------------
    function addAgent(address _agent) external onlyOwner {
        agents[_agent] = true;
        emit AgentAdded(_agent);
    }

    function removeAgent(address _agent) external onlyOwner {
        agents[_agent] = false;
        emit AgentRemoved(_agent);
    }

    // ----------------------------
    // Receipt Token Management
    // ----------------------------
    function setReceiptToken(address token) external onlyOwner {
        receiptToken = ReceiptToken(token);
    }

    function setTokenUnit(uint256 _tokenUnit) external onlyOwner {
        require(_tokenUnit > 0, "tokenUnit must be > 0");
        tokenUnit = _tokenUnit;
    }

    // ----------------------------
    // Bill Lifecycle
    // ----------------------------
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

    function contribute(uint256 billId) external payable nonReentrant {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        require(msg.value > 0, "no eth sent");
        require(!b.withdrawn, "bill already withdrawn");

        uint256 remaining = (b.totalPaid >= b.target) ? 0 : (b.target - b.totalPaid);
        uint256 accepted = msg.value;
        uint256 surplus = 0;

        if (remaining == 0) {
            accepted = 0;
            surplus = msg.value;
        } else if (msg.value > remaining) {
            accepted = remaining;
            surplus = msg.value - remaining;
        }

        if (accepted > 0) {
            contributions[billId][msg.sender] += accepted;
            b.totalPaid += accepted;

            emit Contributed(billId, msg.sender, accepted, b.totalPaid);

            if (address(receiptToken) != address(0)) {
                uint256 tokenAmount = accepted / tokenUnit;
                if (tokenAmount > 0) {
                    receiptToken.mint(msg.sender, tokenAmount);
                }
            }
        }

        if (surplus > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: surplus}("");
            require(refunded, "refund failed");
        }
    }

    function isFunded(uint256 billId) public view returns (bool) {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        return b.totalPaid >= b.target;
    }

    // ----------------------------
    // Withdraw / Refund
    // ----------------------------
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

    function refund(uint256 billId, address contributor) external nonReentrant {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        if (b.withdrawn) revert AlreadyWithdrawn();
        if (b.deadline == 0 || block.timestamp <= b.deadline) revert DeadlineNotPassed();
        if (b.totalPaid >= b.target) revert NotFunded();

        uint256 contributed = contributions[billId][contributor];
        if (contributed == 0) revert NoContribution();

        contributions[billId][contributor] = 0;
        b.totalPaid -= contributed;

        if (address(receiptToken) != address(0)) {
            uint256 tokenAmount = contributed / tokenUnit;
            if (tokenAmount > 0) {
                receiptToken.burn(contributor, tokenAmount);
            }
        }

        (bool ok, ) = payable(contributor).call{value: contributed}("");
        require(ok, "refund transfer failed");

        emit Refunded(billId, contributor, contributed);
    }

    // ----------------------------
    // Reward Management
    // ----------------------------
    function seedRewardPool(uint256 billId) external payable onlyOwner {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        require(msg.value > 0, "no value");
        b.rewardPool += msg.value;
    }

    function distributeRewards(uint256 billId) external nonReentrant {
        Bill storage b = bills[billId];
        if (b.target == 0) revert BillNotFound();
        if (b.totalPaid < b.target) revert NotFunded();
        uint256 pool = b.rewardPool;
        require(pool > 0, "no reward pool");

        b.rewardPool = 0;
        (bool ok, ) = payable(owner()).call{value: pool}("");
        require(ok, "reward transfer failed");

        emit RewardPaid(billId, owner(), pool);
    }

    // ----------------------------
    // Agent Functions
    // ----------------------------
    function agentWithdraw(uint256 billId) external onlyAgent nonReentrant {
        withdraw(billId);
    }

    function agentRefund(uint256 billId, address contributor) external onlyAgent nonReentrant {
        refund(billId, contributor);
    }

    function agentDistributeRewards(uint256 billId) external onlyAgent nonReentrant {
        distributeRewards(billId);
    }

    // ----------------------------
    // View Helpers
    // ----------------------------
    function contributorAmount(uint256 billId, address contributor) external view returns (uint256) {
        return contributions[billId][contributor];
    }

    // Rescue ETH
    function rescueETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "rescue failed");
    }

    // Block direct ETH sends
    receive() external payable {
        revert("Use contribute(billId)");
    }

    fallback() external payable {
        revert("Use contribute(billId)");
    }
}
