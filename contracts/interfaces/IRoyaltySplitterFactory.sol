//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRoyaltySplitterFactory {

    function create(address[] memory payees, uint256[] memory shares_) external returns (address);
}