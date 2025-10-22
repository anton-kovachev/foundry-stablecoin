// // SPDX-License-Identifier: MIT
// //What are our invariants?

// // 1. The total supply of DSC should always be less than the total value of the collateral
// // 2. Getter view funtion should never revet <-- evergreen invariant

// pragma solidity ^0.8.19;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentrazlizedStableCoin.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSC private deployer;
//     DSCEngine private dscEngine;
//     DecentralizedStableCoin private dsc;
//     HelperConfig private helperConfig;

//     address private wEth;
//     address private wBtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, dscEngine, helperConfig) = deployer.run();
//         (, , wEth, wBtc, ) = helperConfig.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 dscTotalSupply = dsc.totalSupply();
//         uint256 wEthTotalDeposited = IERC20(wEth).balanceOf(address(dscEngine));
//         uint256 wBtcTotalDeposited = IERC20(wBtc).balanceOf(address(dscEngine));

//         uint256 wEthValueInUsd = dscEngine.getUsdValue(
//             wEth,
//             wEthTotalDeposited
//         );
//         uint256 wBtcValueInUsd = dscEngine.getUsdValue(
//             wBtc,
//             wBtcTotalDeposited
//         );

//         console.log("wEth Usd value ", wEthValueInUsd);
//         console.log("wBtc Usd value ", wBtcValueInUsd);
//         console.log("dsc total supply ", dscTotalSupply);

//         assert(wEthValueInUsd + wBtcValueInUsd >= dscTotalSupply);
//     }
// }
