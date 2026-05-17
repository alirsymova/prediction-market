// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy}   from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock}      from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {PredictionMarketV1} from "../../src/core/PredictionMarketV1.sol";
import {PredictionMarketV2} from "../../src/core/PredictionMarketV2.sol";
import {FeeVault}           from "../../src/core/FeeVault.sol";
import {MockAggregator}     from "../../src/oracles/MockAggregator.sol";
import {ChainlinkAdapter}   from "../../src/oracles/ChainlinkAdapter.sol";
import {IPredictionMarket}  from "../../src/interfaces/IInterfaces.sol";

contract PredictionMarketTest is Test {

    address internal admin   = makeAddr("admin");
    address internal alice   = makeAddr("alice");
    address internal bob     = makeAddr("bob");
    address internal charlie = makeAddr("charlie");

    PredictionMarketV1 internal market;
    FeeVault           internal vault;
    ERC20Mock          internal usdc;
    MockAggregator     internal aggregator;
    ChainlinkAdapter   internal oracle;

    uint256 internal constant INITIAL_LIQ  = 1000e18;
    uint256 internal constant RESOLUTION   = 7 days;
    uint256 internal constant DISPUTE_WIN  = 1 days;

    function setUp() public {
        vm.startPrank(admin);

        usdc = new ERC20Mock();                          // nonce 0
        usdc.mint(admin,   10_000e18);
        usdc.mint(alice,   10_000e18);
        usdc.mint(bob,     10_000e18);
        usdc.mint(charlie, 10_000e18);

        aggregator = new MockAggregator(1e8, 8);         // nonce 1
        oracle     = new ChainlinkAdapter(address(aggregator), 1 hours); // nonce 2

        vault = new FeeVault(usdc, admin);               // nonce 3

        PredictionMarketV1 impl = new PredictionMarketV1(); // nonce 4
        bytes memory initData = abi.encodeWithSelector(
            PredictionMarketV1.initialize.selector,
            "Will ETH reach $5000 by end of 2025?",
            block.timestamp + RESOLUTION,
            DISPUTE_WIN,
            address(oracle),
            address(usdc),
            address(vault),
            admin,
            INITIAL_LIQ
        );

        // proxy будет задеплоен на nonce 5
        address expectedProxy = vm.computeCreateAddress(admin, 5);
        usdc.approve(expectedProxy, type(uint256).max);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData); // nonce 5
        market = PredictionMarketV1(address(proxy));

        vault.grantRole(vault.DEPOSITOR_ROLE(), address(market));
        vm.stopPrank();
    }

    function test_initializeSetsQuestion() public view {
        (string memory q,,,) = market.getMarketInfo();
        assertEq(q, "Will ETH reach $5000 by end of 2025?");
    }

    function test_initializeSetsStateOpen() public view {
        (,, IPredictionMarket.MarketState s,) = market.getMarketInfo();
        assertEq(uint(s), uint(IPredictionMarket.MarketState.Open));
    }

    function test_initializeSetsReserves() public view {
        (uint256 yes, uint256 no) = market.getReserves();
        assertEq(yes, INITIAL_LIQ / 2);
        assertEq(no,  INITIAL_LIQ / 2);
    }

    function test_initializeGrantsRoles() public view {
        assertTrue(market.hasRole(market.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(market.hasRole(market.RESOLVER_ROLE(),      admin));
        assertTrue(market.hasRole(market.PAUSER_ROLE(),        admin));
    }

    function test_initializeRevertsIfCalledTwice() public {
        vm.expectRevert();
        market.initialize(
            "duplicate", block.timestamp + 1 days, 1 days,
            address(oracle), address(usdc), address(vault), admin, 0
        );
    }

    function test_buyYESShares() public {
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        uint256 shares = market.buyShares(market.YES_ID(), 100e18, 1);
        vm.stopPrank();
        assertGt(shares, 0);
        assertEq(market.balanceOf(alice, market.YES_ID()), shares);
    }

    function test_buyNOShares() public {
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        uint256 shares = market.buyShares(market.NO_ID(), 100e18, 1);
        vm.stopPrank();
        assertGt(shares, 0);
        assertEq(market.balanceOf(alice, market.NO_ID()), shares);
    }

    function test_buySharesTransfersCollateral() public {
        uint256 before = usdc.balanceOf(alice);
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        market.buyShares(market.YES_ID(), 100e18, 1);
        vm.stopPrank();
        assertEq(usdc.balanceOf(alice), before - 100e18);
    }

    function test_buySharesRevertsOnSlippage() public {
        uint256 yesId = market.YES_ID();
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        vm.expectRevert();
        market.buyShares(yesId, 100e18, type(uint256).max);
        vm.stopPrank();
    }

    function test_buySharesRevertsInvalidOutcome() public {
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        vm.expectRevert();
        market.buyShares(3, 100e18, 0);
        vm.stopPrank();
    }

    function test_buySharesRevertsZeroAmount() public {
        uint256 yesId = market.YES_ID();
        vm.startPrank(alice);
        vm.expectRevert();
        market.buyShares(yesId, 0, 0);
        vm.stopPrank();
    }

    function test_buySharesUpdatesReserves() public {
        (uint256 yesBefore, uint256 noBefore) = market.getReserves();
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        market.buyShares(market.YES_ID(), 100e18, 1);
        vm.stopPrank();
        (uint256 yesAfter, uint256 noAfter) = market.getReserves();
        assertGt(noAfter,  noBefore);
        assertLt(yesAfter, yesBefore);
    }

    function test_buySharesCollectsFee() public {
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        market.buyShares(market.YES_ID(), 100e18, 1);
        vm.stopPrank();
        assertGt(vault.totalFeesCollected(), 0);
    }

    function _buyYES(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        usdc.approve(address(market), amount);
        shares = market.buyShares(market.YES_ID(), amount, 1);
        vm.stopPrank();
    }

    function test_sellYESShares() public {
        uint256 shares = _buyYES(alice, 100e18);
        uint256 before = usdc.balanceOf(alice);
        vm.startPrank(alice);
        market.setApprovalForAll(address(market), true);
        uint256 out = market.sellShares(market.YES_ID(), shares, 1);
        vm.stopPrank();
        assertGt(out, 0);
        assertEq(usdc.balanceOf(alice), before + out);
        assertEq(market.balanceOf(alice, market.YES_ID()), 0);
    }

    function test_sellSharesRevertsOnSlippage() public {
        uint256 shares = _buyYES(alice, 100e18);
        uint256 yesId = market.YES_ID();
        vm.startPrank(alice);
        vm.expectRevert();
        market.sellShares(yesId, shares, type(uint256).max);
        vm.stopPrank();
    }

    function test_sellSharesRevertsZeroAmount() public {
        uint256 yesId = market.YES_ID();
        vm.startPrank(alice);
        vm.expectRevert();
        market.sellShares(yesId, 0, 0);
        vm.stopPrank();
    }

    function test_closeMarketAfterResolutionTime() public {
        vm.warp(block.timestamp + RESOLUTION + 1);
        market.closeMarket();
        (,, IPredictionMarket.MarketState s,) = market.getMarketInfo();
        assertEq(uint(s), uint(IPredictionMarket.MarketState.Closed));
    }

    function test_closeMarketRevertsBeforeTime() public {
        vm.expectRevert();
        market.closeMarket();
    }

    function test_resolveMarket() public {
        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + RESOLUTION + 1);
        market.closeMarket();
        vm.prank(admin);
        market.resolveMarket(yesId);
        (,,, IPredictionMarket.Outcome o) = market.getMarketInfo();
        assertEq(uint(o), uint(IPredictionMarket.Outcome.YES));
    }

    function test_resolveMarketRevertsIfNotResolver() public {
        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + RESOLUTION + 1);
        market.closeMarket();
        vm.prank(alice);
        vm.expectRevert();
        market.resolveMarket(yesId);
    }

    function test_settleMarketAfterDisputeWindow() public {
        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + RESOLUTION + 1);
        market.closeMarket();
        vm.prank(admin);
        market.resolveMarket(yesId);
        vm.warp(block.timestamp + DISPUTE_WIN + 1);
        market.settleMarket();
        (,, IPredictionMarket.MarketState s,) = market.getMarketInfo();
        assertEq(uint(s), uint(IPredictionMarket.MarketState.Settled));
    }

    function test_disputeResolutionWithinWindow() public {
        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + RESOLUTION + 1);
        market.closeMarket();
        vm.prank(admin);
        market.resolveMarket(yesId);
        market.disputeResolution();
        (,, IPredictionMarket.MarketState s,) = market.getMarketInfo();
        assertEq(uint(s), uint(IPredictionMarket.MarketState.Disputed));
    }

    function test_resolveDisputeByAdmin() public {
        uint256 yesId = market.YES_ID();
        uint256 noId  = market.NO_ID();
        vm.warp(block.timestamp + RESOLUTION + 1);
        market.closeMarket();
        vm.prank(admin);
        market.resolveMarket(yesId);
        market.disputeResolution();
        vm.prank(admin);
        market.resolveDispute(noId);
        (,,, IPredictionMarket.Outcome o) = market.getMarketInfo();
        assertEq(uint(o), uint(IPredictionMarket.Outcome.NO));
    }

    function _settleYES() internal {
        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + RESOLUTION + 1);
        market.closeMarket();
        vm.prank(admin);
        market.resolveMarket(yesId);
        vm.warp(block.timestamp + DISPUTE_WIN + 1);
        market.settleMarket();
    }

    function test_claimWinnings() public {
        uint256 shares = _buyYES(alice, 100e18);
        _settleYES();
        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = market.claimWinnings();
        assertGt(payout, 0);
        assertEq(usdc.balanceOf(alice), before + payout);
        assertEq(market.balanceOf(alice, market.YES_ID()), 0);
    }

    function test_claimRevertsIfNothingToClaim() public {
        _settleYES();
        vm.prank(bob);
        vm.expectRevert();
        market.claimWinnings();
    }

    function test_claimRevertsIfAlreadyClaimed() public {
        _buyYES(alice, 100e18);
        _settleYES();
        vm.prank(alice); market.claimWinnings();
        vm.prank(alice);
        vm.expectRevert();
        market.claimWinnings();
    }

    function test_loserCannotClaim() public {
        vm.startPrank(bob);
        usdc.approve(address(market), 100e18);
        market.buyShares(market.NO_ID(), 100e18, 1);
        vm.stopPrank();
        _settleYES();
        vm.prank(bob);
        vm.expectRevert();
        market.claimWinnings();
    }

    function test_addLiquidity() public {
        vm.startPrank(charlie);
        usdc.approve(address(market), 200e18);
        market.addLiquidity(100e18, 100e18);
        vm.stopPrank();
        assertGt(market.lpShares(charlie), 0);
    }

    function test_removeLiquidity() public {
        vm.startPrank(charlie);
        usdc.approve(address(market), 200e18);
        market.addLiquidity(100e18, 100e18);
        uint256 shares = market.lpShares(charlie);
        uint256 before = usdc.balanceOf(charlie);
        market.removeLiquidity(shares);
        vm.stopPrank();
        assertEq(market.lpShares(charlie), 0);
        assertGt(usdc.balanceOf(charlie), before);
    }

    function test_pauseStopsBuying() public {
        uint256 yesId = market.YES_ID();
        vm.prank(admin);
        market.pause();
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        vm.expectRevert();
        market.buyShares(yesId, 100e18, 1);
        vm.stopPrank();
    }

    function test_unpauseResumesTrading() public {
        vm.prank(admin); market.pause();
        vm.prank(admin); market.unpause();
        vm.startPrank(alice);
        usdc.approve(address(market), 100e18);
        uint256 shares = market.buyShares(market.YES_ID(), 100e18, 1);
        vm.stopPrank();
        assertGt(shares, 0);
    }

    function test_onlyPauserCanPause() public {
        vm.prank(alice);
        vm.expectRevert();
        market.pause();
    }

    function test_staleOracleBlocksResolution() public {
        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + RESOLUTION + 1);
        market.closeMarket();
        aggregator.setUpdatedAt(block.timestamp - 2 hours);
        vm.prank(admin);
        vm.expectRevert();
        market.resolveMarket(yesId);
    }

    function test_upgradeToV2() public {
        PredictionMarketV2 implV2 = new PredictionMarketV2();
        vm.prank(admin);
        market.upgradeToAndCall(address(implV2), "");
        PredictionMarketV2 v2 = PredictionMarketV2(address(market));
        assertEq(v2.version(), "2.0.0");
    }

    function test_upgradeRevertsIfNotUpgrader() public {
        PredictionMarketV2 implV2 = new PredictionMarketV2();
        vm.prank(alice);
        vm.expectRevert();
        market.upgradeToAndCall(address(implV2), "");
    }

    function test_upgradePreservesState() public {
        uint256 shares = _buyYES(alice, 100e18);
        PredictionMarketV2 implV2 = new PredictionMarketV2();
        vm.prank(admin);
        market.upgradeToAndCall(address(implV2), "");
        assertEq(market.balanceOf(alice, market.YES_ID()), shares);
        (string memory q,,,) = market.getMarketInfo();
        assertEq(q, "Will ETH reach $5000 by end of 2025?");
    }

    function test_impliedProbabilityAtInit50Percent() public view {
        uint256 p = market.impliedProbabilityYES();
        assertEq(p, 5e17);
    }

    function test_impliedProbabilityShiftsOnBuy() public {
        _buyYES(alice, 500e18);
        uint256 p = market.impliedProbabilityYES();
        assertGt(p, 5e17);
    }
}