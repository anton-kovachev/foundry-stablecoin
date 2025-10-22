// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {Script, console} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address ethUsdPriceFeed;
        address btcUsdPriceFeed;
        address wEth;
        address wBtc;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        console.log("Chainid ", block.chainid);
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        }
        if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaEthConfig()
        public
        view
        returns (NetworkConfig memory networkConfig)
    {
        return
            NetworkConfig({
                ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                btcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                wEth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wBtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getOrCreateAnvilConfig()
        public
        returns (NetworkConfig memory networkConfig)
    {
        if (activeNetworkConfig.ethUsdPriceFeed != address(0)) {
            networkConfig = activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock wEthMock = new ERC20Mock("wETH", "wETH", msg.sender, 1000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        ERC20Mock wBtcMock = new ERC20Mock("wBTC", "wBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        networkConfig.ethUsdPriceFeed = address(ethUsdPriceFeed);
        networkConfig.btcUsdPriceFeed = address(btcUsdPriceFeed);

        networkConfig.wEth = address(wEthMock);
        networkConfig.wBtc = address(wBtcMock);

        // networkConfig.deployerKey = vm.envUint("ANVIL_PRIVATE_KEY");
        networkConfig.deployerKey = DEFAULT_ANVIL_PRIVATE_KEY;
    }
}
