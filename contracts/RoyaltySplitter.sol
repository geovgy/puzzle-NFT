//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";

contract RoyaltySplitter is PaymentSplitter {
    constructor(address[] memory payees, uint256[] memory shares_) PaymentSplitter(payees, shares_) {}
}