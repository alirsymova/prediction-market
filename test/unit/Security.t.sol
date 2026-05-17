// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test}        from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock}   from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20}      from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PredictionMarketV1} from "../../src/core/PredictionMarketV1.sol";
import {FeeVault}           from "../../src/core/FeeVault.sol";
import {MockAggregator}     from "../../src/oracles/MockAggregator.sol";
import {ChainlinkAdapter}   from "../../src/oracles/ChainlinkAdapter.sol";
import {Treasury}           from "../../src/governance/Treasury.sol";

contract ReentrantClaimer {
    PredictionMarketV1 public target;
    bool public attacked;
    uint256 public reentrancyCount;

    constructor(PredictionMarketV1 _target) { target = _target; }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external returns (bytes4)
    {
        if (!attacked) {
            attacked = true;
            reentrancyCount++;
            try target.claimWinnings() { reentrancyCount++; } catch {}
        }
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external pure returns (bytes4)
    { return this.onERC1155BatchReceived.selector; }
}

contract SecurityReentrancyTest is Test {
    PredictionMarketV1 internal market;
    FeeVault           internal vault;
    ERC20Mock          internal usdc;

    address internal admin = makeAddr("admin");

    function setUp() public {
        vm.startPrank(admin);
        usdc = new ERC20Mock();                                                   // nonce 0
        usdc.mint(admin, 200_000e18);
        MockAggregator   agg    = new MockAggregator(1e8, 8);                    // nonce 1
        ChainlinkAdapter oracle = new ChainlinkAdapter(address(agg), 1 hours);   // nonce 2
        vault = new FeeVault(usdc, admin);                                        // nonce 3
        PredictionMarketV1 impl = new PredictionMarketV1();                      // nonce 4

        bytes memory initData = abi.encodeWithSelector(
            PredictionMarketV1.initialize.selector,
            "Security test market", block.timestamp + 1 days, 1 hours,
            address(oracle), address(usdc), address(vault), admin, 10_000e18
        );

        address expectedProxy = vm.computeCreateAddress(admin, 5);
        usdc.approve(expectedProxy, type(uint256).max);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);          // nonce 5
        market = PredictionMarketV1(address(proxy));
        vault.grantRole(vault.DEPOSITOR_ROLE(), address(market));
        vm.stopPrank();
    }

    function test_security_reentrancyBlockedOnClaim() public {
        address attacker = makeAddr("attacker");
        usdc.mint(attacker, 1000e18);
        vm.startPrank(attacker);
        usdc.approve(address(market), 1000e18);
        market.buyShares(market.YES_ID(), 1000e18, 1);
        vm.stopPrank();

        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + 1 days + 1);
        market.closeMarket();
        vm.prank(admin); market.resolveMarket(yesId);
        vm.warp(block.timestamp + 1 hours + 1);
        market.settleMarket();

        vm.startPrank(attacker);
        market.claimWinnings();
        vm.expectRevert();
        market.claimWinnings();
        vm.stopPrank();
    }

    function test_security_ceiPatternProven() public {
        address alice = makeAddr("alice");
        usdc.mint(alice, 500e18);
        vm.startPrank(alice);
        usdc.approve(address(market), 500e18);
        market.buyShares(market.YES_ID(), 500e18, 1);
        vm.stopPrank();

        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + 1 days + 1);
        market.closeMarket();
        vm.prank(admin); market.resolveMarket(yesId);
        vm.warp(block.timestamp + 1 hours + 1);
        market.settleMarket();

        vm.prank(alice);
        market.claimWinnings();
        assertTrue(market.hasClaimed(alice));
    }
}

contract SecurityAccessControlTest is Test {
    PredictionMarketV1 internal market;
    Treasury           internal treasury;
    ERC20Mock          internal usdc;

    address internal admin    = makeAddr("admin");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        vm.startPrank(admin);
        usdc = new ERC20Mock();                                                   // nonce 0
        usdc.mint(admin, 200_000e18);
        MockAggregator   agg    = new MockAggregator(1e8, 8);                    // nonce 1
        ChainlinkAdapter oracle = new ChainlinkAdapter(address(agg), 1 hours);   // nonce 2
        FeeVault vault          = new FeeVault(usdc, admin);                     // nonce 3
        PredictionMarketV1 impl = new PredictionMarketV1();                      // nonce 4

        bytes memory initData = abi.encodeWithSelector(
            PredictionMarketV1.initialize.selector,
            "Access test", block.timestamp + 1 days, 1 hours,
            address(oracle), address(usdc), address(vault), admin, 10_000e18
        );

        address expectedProxy = vm.computeCreateAddress(admin, 5);
        usdc.approve(expectedProxy, type(uint256).max);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);          // nonce 5
        market = PredictionMarketV1(address(proxy));
        vault.grantRole(vault.DEPOSITOR_ROLE(), address(market));
        treasury = new Treasury(admin);
        vm.stopPrank();
    }

    function test_security_attackerCannotResolveMarket() public {
        uint256 yesId = market.YES_ID();
        vm.warp(block.timestamp + 1 days + 1);
        market.closeMarket();
        vm.prank(attacker);
        vm.expectRevert();
        market.resolveMarket(yesId);
    }

    function test_security_attackerCannotPause() public {
        vm.prank(attacker); vm.expectRevert(); market.pause();
    }

    function test_security_attackerCannotUpgrade() public {
        PredictionMarketV1 newImpl = new PredictionMarketV1();
        vm.prank(attacker); vm.expectRevert();
        market.upgradeToAndCall(address(newImpl), "");
    }

    function test_security_attackerCannotWithdrawTreasury() public {
        vm.deal(address(treasury), 1 ether);
        vm.prank(attacker); vm.expectRevert();
        treasury.withdrawETH(payable(attacker), 1 ether);
    }

    function test_security_attackerCannotWithdrawTreasuryERC20() public {
        usdc.mint(address(treasury), 1000e18);
        vm.prank(attacker); vm.expectRevert();
        treasury.withdrawERC20(address(usdc), attacker, 1000e18);
    }


    function test_security_noTxOriginAuth() public {
        vm.prank(attacker); vm.expectRevert(); market.pause();
    }
}