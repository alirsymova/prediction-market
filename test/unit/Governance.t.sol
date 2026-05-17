// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test}              from "forge-std/Test.sol";
import {IGovernor}         from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernanceToken}  from "../../src/governance/GovernanceToken.sol";
import {MarketGovernor}   from "../../src/governance/MarketGovernor.sol";
import {MarketTimelock}   from "../../src/governance/MarketGovernor.sol";
import {Treasury}         from "../../src/governance/Treasury.sol";

contract GovernanceTest is Test {

    GovernanceToken internal token;
    MarketTimelock  internal timelock;
    MarketGovernor  internal governor;
    Treasury        internal treasury;

    address internal admin   = makeAddr("admin");
    address internal alice   = makeAddr("alice");
    address internal bob     = makeAddr("bob");
    address internal charlie = makeAddr("charlie");

    uint256 constant DELAY         = 2 days;
    uint256 constant VOTING_DELAY  = 7200;   // blocks
    uint256 constant VOTING_PERIOD = 50400;  // blocks

    function setUp() public {
        vm.startPrank(admin);

        token = new GovernanceToken(admin);

        // Distribute tokens
        token.transfer(alice,   2_000_000e18);
        token.transfer(bob,     1_000_000e18);
        token.transfer(charlie, 500_000e18);

        // Self-delegate to activate voting power
        vm.stopPrank();
        vm.prank(alice);   token.delegate(alice);
        vm.prank(bob);     token.delegate(bob);
        vm.prank(charlie); token.delegate(charlie);
        vm.prank(admin);   token.delegate(admin);
        vm.roll(block.number + 1); // checkpoint must be mined

        vm.startPrank(admin);

        // Deploy Timelock
        address[] memory proposers = new address[](0); // set after governor
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute
        timelock = new MarketTimelock(DELAY, proposers, executors, admin);

        // Deploy Governor
        governor = new MarketGovernor(token, timelock);

        // Setup Timelock roles: only Governor can propose
        timelock.grantRole(timelock.PROPOSER_ROLE(),  address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        // Renounce admin role from deployer
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), admin);

        // Deploy Treasury owned by Timelock
        treasury = new Treasury(address(timelock));

        vm.stopPrank();
    }

    // ─── Token Tests ──────────────────────────────────────────────────────

    function test_totalSupply() public view {
        assertEq(token.totalSupply(), 10_000_000e18);
    }

    function test_delegationActivatesVotingPower() public view {
        assertEq(token.getVotes(alice), 2_000_000e18);
    }

    function test_undelegatedHasNoVotingPower() public {
        address undelgated = makeAddr("undelegated");
        vm.prank(admin);
        token.transfer(undelgated, 100_000e18);
        // No delegation → no votes
        assertEq(token.getVotes(undelgated), 0);
    }

    function test_mintOnlyOwner() public {
        // After transferring ownership to timelock this would need a proposal
        // For now admin still owns
        vm.prank(admin);
        token.mint(alice, 1000e18);
        assertGt(token.totalSupply(), 10_000_000e18);
    }

    function test_mintRevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1000e18);
    }

    // ─── Governor Config Tests ────────────────────────────────────────────

    function test_votingDelay() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
    }

    function test_votingPeriod() public view {
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    function test_quorumFraction() public view {
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_proposalThreshold() public view {
        assertEq(governor.proposalThreshold(), 100_000e18);
    }

    function test_timelockDelay() public view {
        assertEq(timelock.getMinDelay(), DELAY);
    }

    // ─── Full Governance Lifecycle ────────────────────────────────────────
    // propose → vote → queue → execute

    function _propose(address target, bytes memory callData, string memory desc)
        internal returns (uint256 proposalId)
    {
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = target;
        calldatas[0] = callData;

        vm.prank(alice); // alice has 2M tokens > 100k threshold
        proposalId = governor.propose(targets, values, calldatas, desc);
    }

    function test_fullGovernanceLifecycle() public {
        // 1. Fund treasury with some ETH
        vm.deal(address(treasury), 1 ether);

        // 2. Propose: withdraw 0.1 ETH to alice
        bytes memory callData = abi.encodeWithSelector(
            Treasury.withdrawETH.selector,
            payable(alice),
            0.1 ether
        );
        uint256 proposalId = _propose(address(treasury), callData, "Withdraw 0.1 ETH to alice");

        // 3. Wait for voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // 4. Vote
        vm.prank(alice);   governor.castVote(proposalId, 1); // For
        vm.prank(bob);     governor.castVote(proposalId, 1); // For
        vm.prank(charlie); governor.castVote(proposalId, 0); // Against

        // 5. Wait for voting period to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint(governor.state(proposalId)), uint(IGovernor.ProposalState.Succeeded));

        // 6. Queue
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);
        targets[0]   = address(treasury);
        calldatas[0] = callData;
        bytes32 descHash = keccak256(bytes("Withdraw 0.1 ETH to alice"));

        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint(governor.state(proposalId)), uint(IGovernor.ProposalState.Queued));

        // 7. Wait for timelock delay
        vm.warp(block.timestamp + DELAY + 1);

        // 8. Execute
        uint256 aliceBefore = alice.balance;
        governor.execute(targets, values, calldatas, descHash);

        assertEq(uint(governor.state(proposalId)), uint(IGovernor.ProposalState.Executed));
        assertEq(alice.balance, aliceBefore + 0.1 ether);
    }

    function test_proposalDefeatedIfQuorumNotMet() public {
        bytes memory callData = abi.encodeWithSelector(
            Treasury.withdrawETH.selector, payable(alice), 0.1 ether
        );
        uint256 proposalId = _propose(address(treasury), callData, "Quorum test");

        vm.roll(block.number + VOTING_DELAY + 1);

        // Only charlie votes (500k < 4% of 10M = 400k... actually 500k > 400k so quorum IS met)
        // Use a fresh tiny voter instead
        address tiny = makeAddr("tiny");
        vm.prank(admin); token.transfer(tiny, 1000e18);
        vm.prank(tiny);  token.delegate(tiny);
        vm.roll(block.number + 1);

        // tiny votes For but quorum not reached (1000 << 400_000)
        vm.prank(tiny); governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint(governor.state(proposalId)), uint(IGovernor.ProposalState.Defeated));
    }

    function test_proposalRevertsIfBelowThreshold() public {
        address[] memory targets   = new address[](1);
        uint256[] memory values    = new uint256[](1);
        bytes[]   memory calldatas = new bytes[](1);

        // charlie has 500k > threshold, but let's use someone with < 100k
        address poor = makeAddr("poor");
        vm.prank(admin); token.transfer(poor, 50_000e18);
        vm.prank(poor);  token.delegate(poor);
        vm.roll(block.number + 1);

        vm.prank(poor);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Low threshold proposal");
    }

    // ─── Treasury Tests ───────────────────────────────────────────────────

    function test_treasuryReceivesETH() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(treasury.ethBalance(), 1 ether);
    }

    function test_treasuryRevertsDirectWithdraw() public {
        vm.deal(address(treasury), 1 ether);
        vm.prank(admin);
        vm.expectRevert();
        treasury.withdrawETH(payable(admin), 1 ether);
    }
}
