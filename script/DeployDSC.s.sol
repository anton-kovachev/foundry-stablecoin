// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentrazlizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run()
        external
        returns (
            DecentralizedStableCoin decentralizedStableCoin,
            DSCEngine dscEngine,
            HelperConfig helperConfig
        )
    {
        helperConfig = new HelperConfig();
        (
            address ethUsdPriceFeed,
            address btcUsdPriceFeed,
            address wEth,
            address wBtc,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        tokenAddresses.push(wEth);
        tokenAddresses.push(wBtc);

        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.startBroadcast(deployerKey);
        decentralizedStableCoin = new DecentralizedStableCoin();

        dscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(decentralizedStableCoin)
        );

        decentralizedStableCoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
    }
}
