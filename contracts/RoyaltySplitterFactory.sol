//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RoyaltySplitter.sol";
import "./interfaces/IRoyaltySplitterFactory.sol";

contract RoyaltySplitterFactory is IRoyaltySplitterFactory, Ownable {
    function create(address[] memory payees, uint256[] memory shares_) external override returns (address) {
        address splitter = address(new RoyaltySplitter(payees, shares_));
        return splitter;
    }
}