// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// minimal ERC20 token used to represent contribution receipts.
/// te ExpenseShare contract will be set as the `minter` so it can mint/burn tokens when users contribute or get refunded.

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ReceiptToken is ERC20, Ownable {
    /// address authorized to mint/burn (usually the ExpenseShare contract)
    address public minter;


    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /// set the minter address (only owner can set)
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "ReceiptToken: caller not minter");
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
