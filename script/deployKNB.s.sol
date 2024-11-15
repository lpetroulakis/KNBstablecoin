// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {KNBstablecoin} from "../src/KNBstablecoin.sol";
import {KNBEngine} from "../src/KNBEngine.sol";
import {Helper} from "./Helper.s.sol";

contract deployKNB is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (KNBstablecoin, KNBEngine, Helper) {
        Helper config = new Helper();

        (address wethUSDPriceFeed, address wbtcUSDPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUSDPriceFeed, wbtcUSDPriceFeed];

        vm.startBroadcast(deployerKey);
        KNBstablecoin knb = new KNBstablecoin(address(this));
        KNBEngine engine = new KNBEngine(tokenAddresses, priceFeedAddresses, address(knb));
        // knb.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (knb, engine, config);
    }
}
