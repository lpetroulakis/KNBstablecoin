// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {KNBstablecoin} from "./KNBstablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KNBEngine is ReentrancyGuard {
    ////////////////
    // ERRORS//////
    //////////////
    error KNBEngine__MustBeMoreThanZero();
    error KNBEngine__TokenAddressesAndPricefeedsAreNotEqual();
    error KNBEngine__TokenIsNotAllowed();
    error KNBEngine__TransferFailed();
    error KNBEngine__HealthFactorBroken(uint256 healthFactor);
    error KNBEngine__MintFailed();
    error KNBEngine__HealthFactorOk();
    error KNBEngine__HealthFactorNotImproved();

    ////////////////
    // STATE VARIABLES//////
    //////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10; //this means a 10% bonus for the liquidator

    mapping(address token => address pricefeed) public s_priceFeeds; //this will essentially map the addresses to the prices since we know which we'll put inot the list
    mapping(address user => mapping(address token => uint256)) private s_userCollateralDeposited; //this will map the user to the token and the amount of collateral they have, ksince they may have deposited both weth and wbtc
    mapping(address user => uint256 amountKNBMinted) private s_KNBMinted;
    address[] private s_collateralTokens;

    KNBstablecoin private immutable i_KNB;

    //////////////////
    // EVENTS//////
    //////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    //////////////////
    // MODIFIERS//////
    //////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert KNBEngine__MustBeMoreThanZero();
        }
        _;
    }

    // if the token is not allowed as collateral, then revert
    modifier isAllowedToken(address _tokenAddress) {
        //check if the token is allowed
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert KNBEngine__TokenIsNotAllowed();
        }
        _;
    }

    //////////////////
    // FUNCTIONS//////
    //////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address KNBaddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert KNBEngine__TokenAddressesAndPricefeedsAreNotEqual();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_KNB = KNBstablecoin(KNBaddress);
    }

    //////////////////
    // EXTERNAL FUNCTIONS//////
    //////////////////

    /*
    * @dev deposit collateral and mint KNB
    * @param collateralTokenAddress the address of the collateral token, so it's weth or wbtc
    * @param amountCollateral the amount of collateral to deposit
    * this is one of the most important functions of the protocol
    */
    function depositCollateralForKNB(address collateralTokenAddress, uint256 amountCollateral, uint256 amountKNBtoMint)
        external
    {
        depositCollateral(collateralTokenAddress, amountCollateral);
        mintKNB(amountKNBtoMint);
    }

    /*
        * @dev deposit collateral 
        * @param collateralTokenAddress the address of the collateral token, so it's weth or wbtc
        * @param amountCollateral the amount of collateral to deposit
        */
    function depositCollateral(address collateralTokenAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(collateralTokenAddress)
        nonReentrant
    {
        s_userCollateralDeposited[msg.sender][collateralTokenAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, collateralTokenAddress, amountCollateral);
        bool success = IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert KNBEngine__TransferFailed();
        }
    }

    // in order to redeem collateral, the user must keep their health factor above the minimum health factor AFTER the tx
    function redeemCollateralForKNB(address collateralTokenAddress, uint256 amountCollateral, uint256 amountKnbToBurn)
        external
    {
        burnKNB(amountKnbToBurn);
        redeemCollateral(collateralTokenAddress, amountCollateral);
    }

    function redeemCollateral(address collateralTokenAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(collateralTokenAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthIsBroken(msg.sender);
    }

    /*
        * @dev mint KNB
        * @param amountKNBtoMint the amount of KNB to mint, it has to check if the user has enough collateral to mint the amount of KNB
        */
    function mintKNB(uint256 amountKNBtoMint) public moreThanZero(amountKNBtoMint) {
        s_KNBMinted[msg.sender] += amountKNBtoMint;
        _revertIfHealthIsBroken(msg.sender);
        bool minted = i_KNB.mint(msg.sender, amountKNBtoMint);
        if (!minted) {
            revert KNBEngine__MintFailed();
        }
    }

    function burnKNB(uint256 amount) public moreThanZero(amount) {
        _burnKnb(amount, msg.sender, msg.sender);
        _revertIfHealthIsBroken(msg.sender);
    }
    /*
        * @dev this is one of the most important functions of the protocol
        * @param collateral the collateral token address
        * @param user the user to liquidate because their health factor is below the threshold
        * @param debtToCover the amount of debt to cover, you can partially cover it and you take a bonus for doing so
        */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _getHealthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert KNBEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnKnb(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _getHealthFactor(user);
        if (endingUserHealthFactor <= MIN_HEALTH_FACTOR) {
            revert KNBEngine__HealthFactorNotImproved();
        }
        _revertIfHealthIsBroken(msg.sender);
    }

    function calculateHealthFactor(uint256 totalKNBMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalKNBMinted, collateralValueInUsd);
    }

    function getHealthFactor() external view {}

    // =================================
    // INTERNAL FUNCTIONS
    // PRIVATE FUNCTIONS
    // =================================

    // when used it will make other functions revert if the user does not have enough collateral
    function _revertIfHealthIsBroken(address user) internal view {
        uint256 userHealthFactor = _getHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert KNBEngine__HealthFactorBroken(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalKNBMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalKNBMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalKNBMinted;
    }

    function _burnKnb(uint256 amountKnbToBurn, address KnbOriginalOwner, address KnbFrom) private {
        s_KNBMinted[KnbOriginalOwner] -= amountKnbToBurn;
        bool success = i_KNB.transferFrom(KnbFrom, address(this), amountKnbToBurn);
        if (!success) {
            revert KNBEngine__TransferFailed();
        }
        i_KNB.burn(amountKnbToBurn);
    }

    // this will show if a user is close to being liquidated, so we need their minted KNB and the VALUE of their collateral
    function _getHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalKNBMinted, uint256 collateralValueInUsd) = _getUserInfo(user);
        uint256 collateralAdjusted = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjusted * PRECISION) / totalKNBMinted;
    }

    function _getUserInfo(address user) private view returns (uint256 totalKNBMinted, uint256 collateralValueInUsd) {
        totalKNBMinted = s_KNBMinted[user];
        collateralValueInUsd = getCollateralValueInUsd(user);
    }

    function _redeemCollateral(address collateralTokenAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_userCollateralDeposited[from][collateralTokenAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, collateralTokenAddress, amountCollateral);

        bool success = IERC20(collateralTokenAddress).transfer(to, amountCollateral);
        if (!success) {
            revert KNBEngine__TransferFailed();
        }
    }

    // =================================
    // PUBLIC VIEW FUNCTIONS
    // EXTERNAL VIEW FUNCTIONS
    // =================================

    function getTokenAmountFromUsd(address token, uint256 amountUsdInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (amountUsdInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getCollateralValueInUsd(address user) public view returns (uint256 collateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_userCollateralDeposited[user][token];
            collateralValueInUsd += getValueInUsd(token, amount);
        }
        return collateralValueInUsd;
    }

    function getValueInUsd(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getUserInfo(address user) external view returns (uint256 totalKNBMinted, uint256 collateralValueInUsd) {
        (totalKNBMinted, collateralValueInUsd) = _getUserInfo(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_userCollateralDeposited[user][token];
    }
}
