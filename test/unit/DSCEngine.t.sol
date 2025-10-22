// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentrazlizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngineTest is Test {
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 10000 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 20 ether;
    uint256 private constant LIQUADATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATOR_BONUS = 10;

    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    DecentralizedStableCoin private dsc;
    DSCEngine private dscEngine;
    DeployDSC private deployer;
    HelperConfig private helperConfig;

    address ethUsdPriceFeed;
    address wEth;

    address btcUsdPriceFeed;
    address wBtc;

    uint256 deployerKey;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (
            ethUsdPriceFeed,
            btcUsdPriceFeed,
            wEth,
            wBtc,
            deployerKey
        ) = helperConfig.activeNetworkConfig();

        ERC20Mock(wEth).mint(USER, STARTING_ERC20_BALANCE);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testReverIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(wEth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength
                .selector
        );

        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(wEth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testRevertDepositCollateralIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(wEth, 0);

        vm.stopPrank();
    }

    function testCanDepositCollateralIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertDepositCollateralAndMintDscIfBreaksHealthFactorWithOne()
        public
    {
        uint256 amountToMint = (dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL) /
            2) + 1;
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            amountToMint,
            dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL)
        );

        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.depositCollateralAndMintDsc(
            wEth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
    }

    function testRevertDepositCollateralAndMintDscIfBreaksHealthFactor()
        public
    {
        uint256 amountToMint = dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            amountToMint,
            dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL)
        );

        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.depositCollateralAndMintDsc(
            wEth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
    }

    function testCanDepositCollateralAndMintDscWithoutBreakingHealthFactor()
        public
    {
        uint256 amountToMint = dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL) /
            2;

        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            wEth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(
            wEth,
            AMOUNT_COLLATERAL
        );
        assertEq(expectedCollateralValueInUsd, collateralValueInUsd);
        assertEq(amountToMint, totalDscMinted);
    }

    function testCanDepositCollateralAndMintDscEmitCollateralDepositedEvent()
        public
    {
        uint256 amountToMint = dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL) /
            2;

        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, false, true, address(dscEngine));
        emit DSCEngine.CollateralDeposited(USER, wEth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(
            wEth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
    }

    function testRevertDepositCollateralAndMintDscUnsupportedToken() public {
        ERC20Mock testToken = new ERC20Mock("RAN", "RAN", USER, 100e18);
        uint256 amountToMint = dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL) /
            2;
        vm.prank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine__TokenNotAllowedAsCollateral.selector
        );
        dscEngine.depositCollateralAndMintDsc(
            address(testToken),
            AMOUNT_COLLATERAL,
            amountToMint
        );
    }

    function testRevertDepositCollateralAndMintDscZeroCollateral() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateralAndMintDsc(wEth, 0, 0);
    }

    function testRevertDepositCollateralAndMintDscUnapprovedCollateralTransfer()
        public
    {
        uint256 amountToMint = dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL) /
            2;
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.depositCollateralAndMintDsc(
            wEth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 expectedTokenAmount = 0.5 ether;
        uint256 usdAmount = 1000 ether;
        uint256 tokenAmountInUsd = dscEngine.getTokenAmountFromUsd(
            wEth,
            usdAmount
        );

        assertEq(expectedTokenAmount, tokenAmountInUsd);
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        console.log("Ran token address ", address(ranToken));
        vm.startPrank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine__TokenNotAllowedAsCollateral.selector
        );
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndMintDscIfCollateralMoreThanZero()
        public
    {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approveInternal(
            USER,
            address(dscEngine),
            AMOUNT_COLLATERAL
        );
        dscEngine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approveInternal(
            USER,
            address(dscEngine),
            AMOUNT_COLLATERAL
        );

        dscEngine.depositCollateralAndMintDsc(
            wEth,
            AMOUNT_COLLATERAL,
            AMOUNT_DSC_TO_MINT
        );
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (, int256 ethUsdPrice, , , ) = AggregatorV3Interface(ethUsdPriceFeed)
            .latestRoundData();

        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValueInUsd = (AMOUNT_COLLATERAL *
            (uint256(ethUsdPrice) * 1e10)) / 1e18;
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(
            wEth,
            expectedCollateralValueInUsd
        );

        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(expectedCollateralValueInUsd, collateralValueInUsd);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testRevertMintDscIfHealthFactorIsBelowOne()
        public
        depositedCollateral
    {
        uint256 collateralAmountInUsd = dscEngine.getUsdValue(
            wEth,
            AMOUNT_COLLATERAL
        );

        uint256 threshold = 2e18;
        uint256 precision = 1e18;
        uint256 dscToMint = (((collateralAmountInUsd) * 50) / 100) + 1;

        // Calculate expected health factor that will be returned
        uint256 expectedHealthFactor = (collateralAmountInUsd * precision) /
            dscToMint /
            2;
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.mintDsc(dscToMint);
    }

    function testCanHealthFactorGoBelowZero()
        public
        depositedCollateralAndMintDsc
    {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8);
        uint256 expectedHealthFactor = 500000000000000000;

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 healthFactor = dscEngine.calculateHealthFactor(
            totalDscMinted,
            collateralValueInUsd
        );
        assertEq(expectedHealthFactor, healthFactor);
    }

    function testCanMintDsc() public depositedCollateral {
        uint256 collateralAmountInUsd = dscEngine.getUsdValue(
            wEth,
            AMOUNT_COLLATERAL
        );

        uint256 threshold = 2e18;
        uint256 precision = 1e18;
        uint256 dscToMint = ((collateralAmountInUsd * precision) / threshold) -
            1;

        // Calculate expected health factor that will be returned
        vm.startPrank(USER);
        dscEngine.mintDsc(dscToMint);
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(totalDscMinted, dscToMint);
    }

    function testRevertRedeemMoreCollateralThanDeposited()
        public
        depositedCollateral
    {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__InsufficientCollateral.selector);
        dscEngine.redeemCollateral(wEth, AMOUNT_COLLATERAL + 1);
    }

    function testCanRedeemAllDepositedCollateral() public depositedCollateral {
        vm.prank(USER);
        dscEngine.redeemCollateral(wEth, AMOUNT_COLLATERAL);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
    }

    function testCanRedeemAllDepositedCollateralEmitRedeemCollateralEvent()
        public
        depositedCollateral
    {
        vm.prank(USER);
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit DSCEngine.CollateralRedeemed(USER, USER, wEth, AMOUNT_COLLATERAL);
        dscEngine.redeemCollateral(wEth, AMOUNT_COLLATERAL);
    }

    function testCanRedeemMoreThanDepositedCollateral()
        public
        depositedCollateral
    {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__InsufficientCollateral.selector);
        dscEngine.redeemCollateral(wEth, AMOUNT_COLLATERAL + 1 ether);
    }

    function testRevertRedeemZeroCollateral() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(wEth, 0);
    }

    function testRevertRedeemMoreThanDepositedCollateral()
        public
        depositedCollateral
    {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__InsufficientCollateral.selector);
        dscEngine.redeemCollateral(wEth, AMOUNT_COLLATERAL + 1);
    }

    function testRevertRedeemAlmostAllDepositedCollateral()
        public
        depositedCollateralAndMintDsc
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            totalDscMinted,
            collateralValueInUsd -
                dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL - 1 ether)
        );
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.redeemCollateral(wEth, AMOUNT_COLLATERAL - 1 ether);
    }

    function testRevertRedeemCollateralForDsc()
        public
        depositedCollateralAndMintDsc
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 dscToBurn = 9999e18;
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            totalDscMinted - dscToBurn,
            0
        );

        vm.startPrank(USER);
        dsc.approve(address(dscEngine), dscToBurn);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.redeemCollateralForDsc(wEth, AMOUNT_COLLATERAL, dscToBurn);
        vm.stopPrank();
    }

    function testCanRedeemCollateralForDsc()
        public
        depositedCollateralAndMintDsc
    {
        uint256 collateralToRedeem = 1.5 ether;
        uint256 dscToBurn = dscEngine.getUsdValue(wEth, collateralToRedeem);

        vm.startPrank(USER);
        dsc.approve(address(dscEngine), dscToBurn);
        dscEngine.redeemCollateralForDsc(wEth, collateralToRedeem, dscToBurn);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT - dscToBurn);
        assertEq(
            collateralValueInUsd,
            dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL - collateralToRedeem)
        );
    }

    function testRevertLiqudationIfHealthFactorIsAboveOne() public {
        uint256 debtToCover = 5 ether;
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(wEth, USER, debtToCover);
    }

    modifier liquidate(
        uint256 dscMinted,
        uint256 debtToCoverInUsd,
        uint256 ethUsdPrice
    ) {
        vm.startPrank(USER);
        ERC20Mock(wEth).approveInternal(
            USER,
            address(dscEngine),
            AMOUNT_COLLATERAL
        );

        dscEngine.depositCollateralAndMintDsc(
            wEth,
            AMOUNT_COLLATERAL,
            dscMinted
        );
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        MockV3Aggregator ethUsdPriceFeedAggregator = MockV3Aggregator(
            ethUsdPriceFeed
        );

        ethUsdPriceFeedAggregator.updateAnswer(int256(ethUsdPrice));
        (totalDscMinted, collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        vm.prank(address(dscEngine));
        dsc.mint(LIQUIDATOR, debtToCoverInUsd);
        vm.prank(LIQUIDATOR);
        dsc.approve(address(dscEngine), debtToCoverInUsd);
        _;
    }

    function testRevertLiquidationIfDebtToCoverIsZero()
        public
        liquidate(6000e18, 3000e18, 1000e18)
    {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.liquidate(wEth, USER, 0);
    }

    function testCanLiquidateIfHealtchFactorBelowOne()
        public
        liquidate(6000e18, 3000e18, 1000e8)
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 debtToCover = dscEngine.getUsdValue(wEth, 3 ether);
        uint256 expectedLiquidationBonus = dscEngine.calculateLiquidatorBonus(
            debtToCover
        );

        vm.prank(LIQUIDATOR);
        dscEngine.liquidate(wEth, USER, debtToCover);

        (
            uint256 totalDscMintedAfterLiquidation,
            uint256 collateralValueInUsdAfterLiqudation
        ) = dscEngine.getAccountInformation(USER);

        uint256 expectedCollateralValueAferLiquidationInUsd = (
            dscEngine.getUsdValue(wEth, AMOUNT_COLLATERAL)
        ) - (debtToCover + expectedLiquidationBonus);

        assertEq(
            expectedCollateralValueAferLiquidationInUsd,
            collateralValueInUsdAfterLiqudation
        );

        assertEq(totalDscMinted - debtToCover, totalDscMintedAfterLiquidation);
    }

    function testRevertLiquidateIfHealthFactorRemainsBelowOne()
        public
        liquidate(6000e18, 500e18, 1000e8)
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 debtToCoverInUsd = dscEngine.getUsdValue(wEth, 0.5 ether);
        uint256 expectedLiquidationBonusInUsd = dscEngine
            .calculateLiquidatorBonus(debtToCoverInUsd);

        uint256 expectedCollateralValueInUsd = collateralValueInUsd -
            debtToCoverInUsd -
            expectedLiquidationBonusInUsd;
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            totalDscMinted - debtToCoverInUsd,
            expectedCollateralValueInUsd
        );

        vm.prank(LIQUIDATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.liquidate(wEth, USER, debtToCoverInUsd);
    }

    function testRevertLiquidateIfHealthFactorRemainsUnchanged()
        public
        liquidate(6000e18, 500e18, 10e8)
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        uint256 debtToCoverInUsd = dscEngine.getUsdValue(wEth, 0.5 ether);
        uint256 expectedLiquidationBonusInUsd = dscEngine
            .calculateLiquidatorBonus(debtToCoverInUsd);

        uint256 expectedCollateralValueInUsd = collateralValueInUsd -
            debtToCoverInUsd -
            expectedLiquidationBonusInUsd;
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            totalDscMinted - debtToCoverInUsd,
            expectedCollateralValueInUsd
        );

        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dscEngine.liquidate(wEth, USER, debtToCoverInUsd);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        assertEq(MIN_HEALTH_FACTOR, minHealthFactor);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = dscEngine.getLiquidationThreshold();
        assertEq(LIQUADATION_THRESHOLD, liquidationThreshold);
    }

    function testLiquidatorBonsu() public {
        uint256 liquidatorBonus = dscEngine.getLiquidatorBonus();
        assertEq(LIQUIDATOR_BONUS, liquidatorBonus);
    }

    function calculateLiquidatorBonus() public {
        uint256 debtToCover = 3000e18;
        uint256 expectedBonus = 300e18;
        uint256 bonus = dscEngine.calculateLiquidatorBonus(debtToCover);

        assertEq(expectedBonus, bonus);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(wEth, collateralTokens[0]);
        assertEq(wBtc, collateralTokens[1]);
    }

    function testGetCollateralTokenPriceFeed() public {
        address wEthPriceFeedAddress = dscEngine.getCollateralTokenPriceFeed(
            wEth
        );
        assertEq(ethUsdPriceFeed, wEthPriceFeedAddress);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 collateralBalanceOfUser = dscEngine.getCollateralBalanceOfUser(
            USER,
            wEth
        );
        assertEq(AMOUNT_COLLATERAL, collateralBalanceOfUser);
    }
}
