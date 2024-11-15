// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {KNBEngine} from "../../src/KNBEngine.sol";
import {deployKNB} from "../../script/deployKNB.s.sol";
import {KNBstablecoin} from "../../src/KNBstablecoin.sol";
import {Helper} from "../../script/Helper.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract KNBEngineTest is Test {
    KNBEngine engine;
    deployKNB deployer;
    KNBstablecoin knb;
    Helper config;
    address weth;
    address ethUSDPriceFeed;
    address btcUSDPriceFeed;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new deployKNB();
        (knb, engine, config) = deployer.run();
        (ethUSDPriceFeed, btcUSDPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // =====================
    // initialization tests
    // =====================

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);

        vm.expectRevert(KNBEngine.KNBEngine__TokenAddressesAndPricefeedsAreNotEqual.selector);
        new KNBEngine(tokenAddresses, priceFeedAddresses, address(knb));
    }

    // ===================
    // price feed tests
    // ===================
    function testGetValueInUsd() public view {
        uint256 ethAmount = 10e18;
        uint256 expectedUsdValue = 30000e18;
        uint256 actualUsdValue = engine.getValueInUsd(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 60 ether;
        uint256 expectedWeth = 0.02 ether; // 60 / 3000 = 0.02
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    // ===================
    // deposit tests
    // ===================

    function testFailsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(KNBEngine.KNBEngine__TransferFailed.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateralToken() public {
        ERC20Mock randomERC20 = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(KNBEngine.KNBEngine__TokenIsNotAllowed.selector);
        engine.depositCollateral(address(randomERC20), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetUserInfo() public depositedCollateral {
        (uint256 totalKNBMinted, uint256 collateralValueInUsd) = engine.getUserInfo(USER);
        uint256 expectedTotalKnbMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalKNBMinted, expectedTotalKnbMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}
