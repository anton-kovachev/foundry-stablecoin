// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DecentralizedStableCoin} from "./DecentrazlizedStableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSC Engine
 * @author Anton
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token = $1 peg.
 * This stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar Pegged
 * - Algorithmically stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC
 *
 * Our DSC system should be always "overcollateralized". At no point, should the value of all collateral <= $value of all DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /////////////
    /// ERRORS ///
    //////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowedAsCollateral();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__InsufficientCollateral();

    /////////////////////
    //      Types      //
    /////////////////////
    using OracleLib for AggregatorV3Interface;

    /////////////////////
    // STATE VARIABLES //
    /////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUADATION_THRESHOLD = 50;
    uint256 private constant LIQUADATION_PRECISION_THRESHOLD = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_PRECISION = 100;
    uint256 private constant LIQUIDATOR_BONUS = 10; //this equals a 10% bonus

    DecentralizedStableCoin private immutable i_dsc;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address token => address priceFeed) private s_priceFeeds; //token to priceFeed
    mapping(address user => uint256 dscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    ///////////////
    //   Event   //
    ///////////////

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    ///////////////
    // Modifiers //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowedAsCollateral();
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }

        //USD Price Feeds: ETH / USD, BTC / USD
        for (uint8 i = 0; i < tokenAddresses.length; i++) {
            s_collateralTokens.push(tokenAddresses[i]);
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////
    // External Function //
    //////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stablecoins to mint
     * @notice this function will deposit your collateral and mint DSC
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transactions.
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    //in order to reedem collateral:
    //1. health factor must be over 1 After collateral pulled
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Threshold to 150%
    // $100 -> $75
    // $50 DSC

    // Hey if, somebody pays back all your minted DSC, they can have all your collateral for a discount

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice the must have more collateral value that the minimum threshold
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;

        //if the minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (minted != true) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //If someone is alsmost under collaterized we will pay you to liqudate them!!
    /**
     *
     * @param collateralToken The erc20 collateral address to liquidate
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to improve the uses health factor
     * @notice You can partially liqudate a user
     * @notice You will get a liqudation bonus for taking the user's funds.
     * @notice This function assume that the protocol will be roughly 200% overcollaterized in order for this to work.
     * @notice A known bug would be if the protocol was 100% or less collateralized then we would be able to incentive the liquidators.
     * For example if the price of the collateral plummeted before anyone could be liquidated
     */
    function liquidate(
        address collateralToken,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        //We want to burn their DSC debt and take their collateral
        //Bad User: $140 ETH $100 DSC
        //debtToCover = $100

        uint256 tokenAmountOfDebtCovered = getTokenAmountFromUsd(
            collateralToken,
            debtToCover
        );
        //Add give them a 10% bonus
        //So we are given the liqudator $110 of WETH for DSC
        //We should implement a feature to liquidate if the protocol is insolvent
        //And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountOfDebtCovered *
            LIQUIDATOR_BONUS) / LIQUIDATOR_PRECISION;
        uint256 totalCollateralToReedem = tokenAmountOfDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            collateralToken,
            totalCollateralToReedem,
            user,
            msg.sender
        );

        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        uint256 liquidatorHealthFactor = _healthFactor(user);

        if (liquidatorHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(liquidatorHealthFactor);
        }
    }

    function getHealthFactor() external view returns (uint256 healthFactor) {
        healthFactor = _healthFactor(msg.sender);
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    ///////////////////////
    // Internal Functions //
    //////////////////////

    function _healthFactor(address user) private view returns (uint256) {
        //total DSC minted
        //total collateralvalue
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) private pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collaterAdjustedForThreshold = ((collateralValueInUsd *
            LIQUADATION_THRESHOLD) / (LIQUADATION_PRECISION_THRESHOLD));
        return (collaterAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        if (
            s_collateralDeposited[from][tokenCollateralAddress] <
            amountCollateral
        ) {
            revert DSCEngine__InsufficientCollateral();
        }

        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
    }

    /*
     *@dev Low-level internal functions. Don't call
     */
    function _burnDsc(
        uint256 amountToBurn,
        address onBehalfOf,
        address dscFrom
    ) private moreThanZero(amountToBurn) {
        s_DSCMinted[onBehalfOf] -= amountToBurn;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToBurn);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountToBurn);
    }

    ///////////////////////
    // Public & External View Functions //
    //////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        //1 ETH = $1000
        //The returned value from CL will be 1000 * 1e18
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 amountInWei
    ) public view returns (uint256) {
        //price of ETH/token
        //$/ETH ??
        //$2000/$1000 = 0.5 ETH
        (, int256 price, , , ) = AggregatorV3Interface(s_priceFeeds[token])
            .staleCheckLatestRoundData();

        //($1000e18 * 1e18) / ($2000e8 * 1e10)
        return
            (amountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(
        address user,
        address collateralToken
    ) public view returns (uint256) {
        return s_collateralDeposited[user][collateralToken];
    }

    function getCollateralTokenPriceFeed(
        address collateralToken
    ) public view returns (address) {
        return s_priceFeeds[collateralToken];
    }

    function getMinHealthFactor() public pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationThreshold() public pure returns (uint256) {
        return LIQUADATION_THRESHOLD;
    }

    function getLiquidatorBonus() public pure returns (uint256) {
        return LIQUIDATOR_BONUS;
    }

    function calculateLiquidatorBonus(
        uint256 debtToCoverInUsd
    ) public pure returns (uint256) {
        return (debtToCoverInUsd * LIQUIDATOR_BONUS) / LIQUIDATOR_PRECISION;
    }
}
