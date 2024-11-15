// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {deployKNB} from "../../script/deployKNB.s.sol";
import {KNBEngine} from "../../src/KNBEngine.sol";
import {KNBstablecoin} from "../../src/KNBstablecoin.sol";
import {Helper} from "../../script/Helper.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    deployKNB deployer;
    KNBEngine engine;
    KNBstablecoin knb;
    Helper config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new deployKNB();
        (knb, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(engine));
        handler = new Handler(engine, knb);
        targetContract(address(handler));
    }

    function invariant_protocolMustAlwaysHaveMoreValueThanSupply() public view {
        uint256 totalSupply = knb.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getValueInUsd(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getValueInUsd(wbtc, totalWbtcDeposited);

        assert((wethValue + wbtcValue) >= totalSupply);
    }
}
