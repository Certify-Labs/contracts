// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LearnAndEarnToken is ERC20, Ownable {
    constructor() ERC20("LearnAndEarnToken", "LET") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000 * 10 ** decimals()); // Initial mint for platform use
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
