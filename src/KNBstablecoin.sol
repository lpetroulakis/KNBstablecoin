// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title KNBstablecoin
 * @author Loukas Petroulakis
 * this will be pegged to the dollar
 * it is going to be governed by our engine contract
 */
contract KNBstablecoin is ERC20Burnable, Ownable {
    error KNBstablecoin__MustBeMoreThanZero();
    error KNBstablecoin__amountIsMoreThanBalance();
    error KNBstablecoin__MustNotBeZeroAddress();

    constructor(address initialOwner) ERC20("KNBstablecoin", "KNB") Ownable(initialOwner) {} //gotta check this one out later

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert KNBstablecoin__MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert KNBstablecoin__amountIsMoreThanBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert KNBstablecoin__MustNotBeZeroAddress();
        }
        if (_amount <= 0) {
            revert KNBstablecoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
