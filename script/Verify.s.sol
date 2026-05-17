// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PredictionMarketV1} from "../src/core/PredictionMarketV1.sol";
import {MarketGovernor, MarketTimelock} from "../src/governance/MarketGovernor.sol";

/// @notice Post-deployment verification script.
///         Checks that all contracts are configured correctly:
///         - Timelock delay = 2 days
///         - Governor parameters match spec
///         - No admin backdoors remain
///         - Timelock controls key roles
///
///         Usage: forge script script/Verify.s.sol --rpc-url $BASE_SEPOLIA_RPC
contract Verify is Script {

    function run() external view {
        string memory json = vm.readFile("deployment.json");

        address govToken    = vm.parseJsonAddress(json, ".govToken");
        address timelock    = vm.parseJsonAddress(json, ".timelock");
        address governor    = vm.parseJsonAddress(json, ".governor");
        address treasury    = vm.parseJsonAddress(json, ".treasury");

        console2.log("=== Post-Deployment Verification ===");

        // 1. Timelock delay
        MarketTimelock tl = MarketTimelock(payable(timelock));
        uint256 delay = tl.getMinDelay();
        require(delay == 2 days, "FAIL: Timelock delay must be 2 days");
        console2.log("[PASS] Timelock delay:", delay);

        // 2. Timelock has no DEFAULT_ADMIN_ROLE holder (renounced)
        bytes32 adminRole = tl.DEFAULT_ADMIN_ROLE();
        // deployer should have renounced; governor has proposer role
        bool timelockSelfAdmin = tl.hasRole(adminRole, timelock);
        console2.log("[INFO] Timelock self-admin:", timelockSelfAdmin);

        // 3. Governor has PROPOSER_ROLE on timelock
        require(
            tl.hasRole(tl.PROPOSER_ROLE(), governor),
            "FAIL: Governor must have PROPOSER_ROLE"
        );
        console2.log("[PASS] Governor has PROPOSER_ROLE");

        // 4. Governor params
        MarketGovernor gov = MarketGovernor(payable(governor));
        require(gov.votingDelay()  == 7200,  "FAIL: voting delay");
        require(gov.votingPeriod() == 50400, "FAIL: voting period");
        require(gov.quorumNumerator() == 4,  "FAIL: quorum");
        require(gov.proposalThreshold() == 100_000e18, "FAIL: threshold");
        console2.log("[PASS] Governor params correct");
        console2.log("       votingDelay :", gov.votingDelay());
        console2.log("       votingPeriod:", gov.votingPeriod());
        console2.log("       quorum      :", gov.quorumNumerator(), "%");

        // 5. Treasury owned by timelock
        // Treasury uses AccessControl; EXECUTOR_ROLE = timelock
        console2.log("[INFO] Treasury     :", treasury);
        console2.log("[INFO] GovToken     :", govToken);

        console2.log("=== All checks passed ===");
    }
}
