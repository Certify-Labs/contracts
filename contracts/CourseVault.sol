// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract CourseVault is ERC4626 {
    constructor(IERC20 asset, string memory courseName)
        ERC4626(asset)
        ERC20(
            string(abi.encodePacked(courseName, " Vault")),
            string(abi.encodePacked("v", bytes(courseName)[0]))
        )
    {}
}
