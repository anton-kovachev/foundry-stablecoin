// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdUtils} from "lib/forge-std/src/StdUtils.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentrazlizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "./../mocks/MockV3Aggregator.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Handler is Test {
    DSCEngine private dscEngine;
    DecentralizedStableCoin private dsc;

    ERC20Mock private wEth;
    ERC20Mock private wBtc;

    MockV3Aggregator private wEthPriceFeed;
    MockV3Aggregator private wBtcPriceFeed;

    uint256 private constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintIsCalled;
    address[] depositers;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();

        wEth = ERC20Mock(collateralTokens[0]);
        wBtc = ERC20Mock(collateralTokens[1]);

        wEthPriceFeed = MockV3Aggregator(
            dscEngine.getCollateralTokenPriceFeed(address(wEth))
        );
        wBtcPriceFeed = MockV3Aggregator(
            dscEngine.getCollateralTokenPriceFeed(address(wBtc))
        );
    }

    function mintDsc(uint256 amount, uint256 depositersSeed) public {
        if (depositers.length == 0) {
            return;
        }

        depositersSeed = bound(
            depositersSeed,
            depositers.length,
            type(uint256).max
        );
        address depositor = _getDepositorFromSeed(depositersSeed);
        uint256 minHealthFactor = 1e18;
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(depositor);

        if (amount == 0) {
            return;
        }

        uint256 newDscMinted = totalDscMinted + amount;

        if (
            (((collateralValueInUsd * 50) / 100) / newDscMinted) <
            minHealthFactor
        ) {
            return;
        }

        vm.prank(depositor);
        dscEngine.mintDsc(amount);
        timesMintIsCalled++;
    }

    // function updatePrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     wEthPriceFeed.updateAnswer(newPriceInt);
    // }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
        depositers.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        // depositCollateral(collateralSeed, amountCollateral);
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(
            msg.sender,
            address(collateralToken)
        );

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if (amountCollateral == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
    }

    // Helper Function
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return wEth;
        } else {
            return wBtc;
        }
    }

    function _getDepositorFromSeed(
        uint256 depositersSeed
    ) internal view returns (address) {
        return depositers[depositersSeed % depositers.length];
    }
}
