// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor}                   from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings}           from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple}     from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes}              from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl}    from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController}         from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes}                     from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title MarketTimelock
/// @notice 2-day timelock that guards all DAO-approved parameter changes.
///         Controls the treasury and MarketFactory configuration.
///         Adapted from Assignment 4.
contract MarketTimelock is TimelockController {
    /// @param minDelay   2 days (172800 seconds) per spec
    /// @param proposers  [Governor address] set post-deployment
    /// @param executors  [address(0)] → anyone can execute after delay
    /// @param admin      deployer — renounced after setup
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address  admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}

/// @title MarketGovernor
/// @notice OpenZeppelin Governor stack for on-chain governance of the
///         Prediction Market protocol.
///
/// @dev    Parameters per spec:
///         - Voting delay:  1 day  (7200 blocks @ 12s)
///         - Voting period: 1 week (50400 blocks)
///         - Quorum:        4%
///         - Proposal threshold: 1% of total supply
///
///         Governs: MarketFactory params, FeeVault fee rates,
///                  dispute window, accepted oracle types.
///
///         Adapted from Assignment 4 MyGovernor.sol.
contract MarketGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    constructor(IVotes _token, TimelockController _timelock)
        Governor("MarketGovernor")
        GovernorSettings(
            7200,   // 1 day voting delay  (blocks)
            50400,  // 1 week voting period (blocks)
            100_000e18  // proposal threshold: ~1% of 10M supply
        )
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4)  // 4% quorum
        GovernorTimelockControl(_timelock)
    {}

    // ─── Required overrides ───────────────────────────────────────────────

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public view override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function proposalThreshold()
        public view override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function state(uint256 proposalId)
        public view override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public view override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal view override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }
}
