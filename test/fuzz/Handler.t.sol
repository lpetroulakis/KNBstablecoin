// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {KNBEngine} from "../../src/KNBEngine.sol";
import {KNBstablecoin} from "../../src/KNBstablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    KNBEngine engine;
    KNBstablecoin knb;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT = type(uint96).max;

    constructor(KNBEngine _engine, KNBstablecoin _knb) {
        engine = _engine;
        knb = _knb;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function mintKNB(uint256 amount) public {
        (uint256 totalKNBMinted, uint256 collateralValue) = engine.getUserInfo(msg.sender);
        int256 maxKNBToMint = (int256(collateralValue) / 2) - int256(totalKNBMinted);
        if (maxKNBToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxKNBToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        engine.mintKNB(amount);
        vm.stopPrank();
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        ERC20Mock collateral = _getCollateralSeed(collateralSeed);
        collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT);

        vm.prank(msg.sender);
        collateral.mint(msg.sender, collateralAmount);
        collateral.approve(address(engine), collateralAmount);
        engine.depositCollateral(address(collateral), collateralAmount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        ERC20Mock collateral = _getCollateralSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(address(collateral), msg.sender);
        collateralAmount = bound(collateralAmount, 0, maxCollateralToRedeem);
        if (collateralAmount == 0) {
            return;
        }
        engine.redeemCollateral(address(collateral), collateralAmount);
    }

    function _getCollateralSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
