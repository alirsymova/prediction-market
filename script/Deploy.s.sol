// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy}     from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20}           from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PredictionMarketV1} from "../src/core/PredictionMarketV1.sol";
import {FeeVault}           from "../src/core/FeeVault.sol";
import {MarketFactory}      from "../src/factory/MarketFactory.sol";
import {GovernanceToken}    from "../src/governance/GovernanceToken.sol";
import {MarketGovernor, MarketTimelock} from "../src/governance/MarketGovernor.sol";
import {Treasury}           from "../src/governance/Treasury.sol";
import {ChainlinkAdapter}   from "../src/oracles/ChainlinkAdapter.sol";

/// @notice Reproducible deployment script.
///         Usage:
///           forge script script/Deploy.s.sol \
///             --rpc-url $BASE_SEPOLIA_RPC \
///             --broadcast \
///             --verify \
///             -vvvv
///
/// @dev    All parameters read from environment or sensible defaults.
///         Script is idempotent — re-running deploys fresh contracts (no state check needed
///         since each deployment is isolated by tx hash in the deployment log).
contract Deploy is Script {

    // ── Config ────────────────────────────────────────────────────────────
    // Base Sepolia ETH/USD Chainlink feed
    address constant CHAINLINK_ETH_USD_BASE_SEPOLIA = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    // Base Sepolia USDC
    address constant USDC_BASE_SEPOLIA              = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    uint256 constant TIMELOCK_DELAY    = 2 days;
    uint256 constant STALENESS        = 1 hours;
    uint256 constant INITIAL_LIQUIDITY = 1000e6; // 1000 USDC (6 decimals)

    struct Deployment {
        address govToken;
        address timelock;
        address governor;
        address treasury;
        address feeVault;
        address marketImpl;
        address marketFactory;
        address oracle;
        address exampleMarket;
    }

    function run() external returns (Deployment memory d) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        address collateral = vm.envOr("COLLATERAL", USDC_BASE_SEPOLIA);
        address feedAddr   = vm.envOr("CHAINLINK_FEED", CHAINLINK_ETH_USD_BASE_SEPOLIA);

        console2.log("=== PredictionMarket Deployment ===");
        console2.log("Deployer  :", deployer);
        console2.log("Collateral:", collateral);
        console2.log("Feed      :", feedAddr);

        vm.startBroadcast(deployerKey);

        // 1. Oracle adapter
        d.oracle = address(new ChainlinkAdapter(feedAddr, STALENESS));
        console2.log("ChainlinkAdapter  :", d.oracle);

        // 2. Governance token
        d.govToken = address(new GovernanceToken(deployer));
        console2.log("GovernanceToken   :", d.govToken);

        // 3. Timelock (proposers set after governor)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute after delay
        d.timelock = address(new MarketTimelock(TIMELOCK_DELAY, proposers, executors, deployer));
        console2.log("MarketTimelock    :", d.timelock);

        // 4. Governor
        d.governor = address(new MarketGovernor(
            GovernanceToken(d.govToken),
            MarketTimelock(payable(d.timelock))
        ));
        console2.log("MarketGovernor    :", d.governor);

        // 5. Wire timelock: only governor can propose
        MarketTimelock tl = MarketTimelock(payable(d.timelock));
        tl.grantRole(tl.PROPOSER_ROLE(),  d.governor);
        tl.grantRole(tl.CANCELLER_ROLE(), d.governor);
        tl.renounceRole(tl.DEFAULT_ADMIN_ROLE(), deployer);

        // 6. Treasury owned by timelock
        d.treasury = address(new Treasury(d.timelock));
        console2.log("Treasury          :", d.treasury);

        // 7. FeeVault
        d.feeVault = address(new FeeVault(IERC20(collateral), deployer));
        console2.log("FeeVault          :", d.feeVault);

        // 8. Market implementation (logic contract for UUPS)
        d.marketImpl = address(new PredictionMarketV1());
        console2.log("MarketImpl (logic):", d.marketImpl);

        // 9. Market factory
        d.marketFactory = address(new MarketFactory(
            d.marketImpl, collateral, d.feeVault, deployer
        ));
        console2.log("MarketFactory     :", d.marketFactory);

        // 10. Grant factory CREATOR_ROLE and vault DEPOSITOR_ROLE
        FeeVault(d.feeVault).grantRole(
            FeeVault(d.feeVault).DEPOSITOR_ROLE(), d.marketFactory
        );

        // 11. Deploy an example market (no initial liquidity for testnet)
        uint256 resolutionTime = block.timestamp + 30 days;
        d.exampleMarket = MarketFactory(d.marketFactory).createMarket(
            "Will ETH exceed $5000 by end of 2025?",
            resolutionTime,
            d.oracle,
            0
        );
        console2.log("ExampleMarket     :", d.exampleMarket);

        vm.stopBroadcast();

        // Write addresses to JSON
        _writeDeployment(d);

        console2.log("=== Deployment complete ===");
    }

    function _writeDeployment(Deployment memory d) internal {
        string memory json = string(abi.encodePacked(
            '{"govToken":"',        vm.toString(d.govToken),
            '","timelock":"',       vm.toString(d.timelock),
            '","governor":"',       vm.toString(d.governor),
            '","treasury":"',       vm.toString(d.treasury),
            '","feeVault":"',       vm.toString(d.feeVault),
            '","marketImpl":"',     vm.toString(d.marketImpl),
            '","marketFactory":"',  vm.toString(d.marketFactory),
            '","oracle":"',         vm.toString(d.oracle),
            '","exampleMarket":"',  vm.toString(d.exampleMarket),
            '"}'
        ));
        vm.writeFile("deployment.json", json);
        console2.log("Addresses written to deployment.json");
    }
}
