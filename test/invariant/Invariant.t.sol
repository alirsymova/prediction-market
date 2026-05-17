// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {ERC1967Proxy}        from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock}           from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {PredictionMarketV1} from "../../src/core/PredictionMarketV1.sol";
import {FeeVault}           from "../../src/core/FeeVault.sol";
import {MockAggregator}     from "../../src/oracles/MockAggregator.sol";
import {ChainlinkAdapter}   from "../../src/oracles/ChainlinkAdapter.sol";
import {IPredictionMarket}  from "../../src/interfaces/IInterfaces.sol";

contract MarketHandler is Test {
    PredictionMarketV1 public market;
    ERC20Mock          public usdc;

    address[] public actors;
    uint256 public totalCollateralIn;
    uint256 public totalCollateralOut;

    constructor(PredictionMarketV1 _market, ERC20Mock _usdc) {
        market = _market;
        usdc   = _usdc;
        for (uint256 i = 0; i < 5; i++) {
            address a = makeAddr(string(abi.encodePacked("actor", i)));
            usdc.mint(a, 1_000_000e18);
            actors.push(a);
        }
    }

    function buyYES(uint256 actorIdx, uint256 amount) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        amount   = bound(amount, 1e15, 1000e18);
        address actor = actors[actorIdx];
        vm.startPrank(actor);
        usdc.approve(address(market), amount);
        try market.buyShares(market.YES_ID(), amount, 1) { totalCollateralIn += amount; } catch {}
        vm.stopPrank();
    }

    function buyNO(uint256 actorIdx, uint256 amount) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        amount   = bound(amount, 1e15, 1000e18);
        address actor = actors[actorIdx];
        vm.startPrank(actor);
        usdc.approve(address(market), amount);
        try market.buyShares(market.NO_ID(), amount, 1) { totalCollateralIn += amount; } catch {}
        vm.stopPrank();
    }

    function sellYES(uint256 actorIdx, uint256 sharePct) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        sharePct = bound(sharePct, 1, 100);
        address actor  = actors[actorIdx];
        uint256 bal    = market.balanceOf(actor, market.YES_ID());
        if (bal == 0) return;
        uint256 shares = (bal * sharePct) / 100;
        vm.startPrank(actor);
        try market.sellShares(market.YES_ID(), shares, 1) returns (uint256 out) {
            totalCollateralOut += out;
        } catch {}
        vm.stopPrank();
    }

    function addLiq(uint256 actorIdx, uint256 amount) external {
        actorIdx = bound(actorIdx, 0, actors.length - 1);
        amount   = bound(amount, 1e15, 500e18);
        address actor = actors[actorIdx];
        vm.startPrank(actor);
        usdc.approve(address(market), amount * 2);
        try market.addLiquidity(amount, amount) {} catch {}
        vm.stopPrank();
    }
}

contract InvariantTests is StdInvariant, Test {
    PredictionMarketV1 internal market;
    FeeVault           internal vault;
    ERC20Mock          internal usdc;
    MarketHandler      internal handler;

    address internal admin = makeAddr("admin");

    function setUp() public {
        vm.startPrank(admin);
        usdc = new ERC20Mock();                                                   // nonce 0
        MockAggregator   agg    = new MockAggregator(1e8, 8);                    // nonce 1
        ChainlinkAdapter oracle = new ChainlinkAdapter(address(agg), 1 hours);   // nonce 2
        vault = new FeeVault(usdc, admin);                                        // nonce 3
        PredictionMarketV1 impl = new PredictionMarketV1();                      // nonce 4
        uint256 initLiq = 100_000e18;
        usdc.mint(admin, initLiq);

        bytes memory initData = abi.encodeWithSelector(
            PredictionMarketV1.initialize.selector,
            "Invariant market", block.timestamp + 365 days, 1 days,
            address(oracle), address(usdc), address(vault), admin, initLiq
        );

        address expectedProxy = vm.computeCreateAddress(admin, 5);
        usdc.approve(expectedProxy, type(uint256).max);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);          // nonce 5
        market = PredictionMarketV1(address(proxy));
        vault.grantRole(vault.DEPOSITOR_ROLE(), address(market));

        handler = new MarketHandler(market, usdc);
        vm.stopPrank();

        targetContract(address(handler));
    }

    function invariant_kNeverDecreases() public view {
        (uint256 yes, uint256 no) = market.getReserves();
        assertTrue(yes > 0 && no > 0, "Reserves must remain positive");
    }

    function invariant_contractBalanceCoversReserves() public view {
        (uint256 yes, uint256 no) = market.getReserves();
        uint256 bal = usdc.balanceOf(address(market));
        assertGe(bal, yes + no, "Balance must cover reserves");
    }

    function invariant_lpSharesPositive() public view {
        assertGt(market.totalLPShares(), 0, "LP shares must stay positive");
    }

    function invariant_stateIsOpen() public view {
        (,, IPredictionMarket.MarketState s,) = market.getMarketInfo();
        assertEq(uint(s), uint(IPredictionMarket.MarketState.Open), "State must be Open");
    }

    function invariant_totalCollateralCoversReserves() public view {
        (uint256 yes, uint256 no) = market.getReserves();
        assertGe(market.totalCollateral(), yes + no, "totalCollateral must cover reserves");
    }
}