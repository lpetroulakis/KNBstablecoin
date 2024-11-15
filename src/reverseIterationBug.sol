// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

contract reverseIterationBug {
    uint256 public counter;

    constructor() {
        counter = 10;
    }

    function incrementCounter() public returns (uint256) {
        counter += 1;
        return counter;
    }

    function getCounterValue() public view returns (uint256) {
        return counter;
    }

    function calculateSum(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b;
    }

    function triggerBug() public returns (uint256) {
        return calculateSum(getCounterValue(), incrementCounter());
    }
}
