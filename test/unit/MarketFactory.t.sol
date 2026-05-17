// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test}        from "forge-std/Test.sol";
import {ERC20Mock}   from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {MarketFactory}      from "../../src/factory/MarketFactory.sol";
import {PredictionMarketV1} from "../../src/core/PredictionMarketV1.sol";
import {FeeVault}           from "../../src/core/FeeVault.sol";
import {MockAggregator}     from "../../src/oracles/MockAggregator.sol";
import {ChainlinkAdapter}   from "../../src/oracles/ChainlinkAdapter.sol";

contract MarketFactoryTest is Test {

    MarketFactory      internal factory;
    PredictionMarketV1 internal impl;
    FeeVault           internal vault;
    ERC20Mock          internal usdc;
    ChainlinkAdapter   internal oracle;

    address internal admin = makeAddr("admin");

    function setUp() public {
        vm.startPrank(admin);
        usdc = new ERC20Mock();
        usdc.mint(admin, 10_000_000e18);

        MockAggregator agg = new MockAggregator(1e8, 8);
        oracle  = new ChainlinkAdapter(address(agg), 1 hours);
        vault   = new FeeVault(usdc, admin);
        impl    = new PredictionMarketV1();
        factory = new MarketFactory(address(impl), address(usdc), address(vault), admin);
        vm.stopPrank();
    }

    function test_createMarketViaCreate() public {
        vm.startPrank(admin);
        usdc.approve(address(factory), 0); // no initial liquidity
        address market = factory.createMarket(
            "Will BTC hit 100k?", block.timestamp + 30 days, address(oracle), 0
        );
        vm.stopPrank();

        assertTrue(factory.isMarket(market));
        assertEq(factory.marketCount(), 1);
    }

    function test_createMarketDeterministic() public {
        bytes32 salt = keccak256("market-1");
        vm.startPrank(admin);

        address predicted = factory.computeAddress(
            salt, "BTC market", block.timestamp + 30 days, address(oracle), 0
        );

        address deployed = factory.createMarketDeterministic(
            "BTC market", block.timestamp + 30 days, address(oracle), 0, salt
        );
        vm.stopPrank();

        assertEq(predicted, deployed, "CREATE2 address must match prediction");
        assertTrue(factory.isMarket(deployed));
    }

    function test_create2SaltCannotBeReused() public {
        bytes32 salt = keccak256("unique-salt");
        vm.startPrank(admin);
        factory.createMarketDeterministic(
            "First", block.timestamp + 30 days, address(oracle), 0, salt
        );
        vm.expectRevert();
        factory.createMarketDeterministic(
            "Second", block.timestamp + 30 days, address(oracle), 0, salt
        );
        vm.stopPrank();
    }

    function test_nonCreatorCannotCreateMarket() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert();
        factory.createMarket("hack", block.timestamp + 1 days, address(oracle), 0);
    }

    function test_getMarketsReturnsAll() public {
        vm.startPrank(admin);
        factory.createMarket("Q1", block.timestamp + 30 days, address(oracle), 0);
        factory.createMarket("Q2", block.timestamp + 30 days, address(oracle), 0);
        factory.createMarket("Q3", block.timestamp + 30 days, address(oracle), 0);
        vm.stopPrank();

        address[] memory markets = factory.getMarkets();
        assertEq(markets.length, 3);
    }

    function test_setDisputeWindow() public {
        vm.prank(admin);
        factory.setDefaultDisputeWindow(2 days);
        assertEq(factory.defaultDisputeWindow(), 2 days);
    }

    function test_setDisputeWindowRevertsIfNotAdmin() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert();
        factory.setDefaultDisputeWindow(2 days);
    }
}
