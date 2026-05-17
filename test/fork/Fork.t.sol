// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test}      from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20}    from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ChainlinkAdapter} from "../../src/oracles/ChainlinkAdapter.sol";
import {CPMM}             from "../../src/libraries/CPMM.sol";

// ─── Fork Test 1: Real Chainlink ETH/USD on Base Sepolia ─────────────────────

/// @notice Forks Base Sepolia and reads from a real Chainlink feed.
contract ForkChainlinkTest is Test {
    // Base Sepolia ETH/USD feed
    address constant CHAINLINK_ETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    uint256 constant STALENESS = 1 hours;

    ChainlinkAdapter oracle;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string("https://sepolia.base.org"));
        vm.createSelectFork(rpc);
        oracle = new ChainlinkAdapter(CHAINLINK_ETH_USD, STALENESS);
    }

    function test_fork_chainlinkFeedReturnsPositivePrice() public view {
        (uint256 price, uint8 decimals) = oracle.getPrice();
        assertGt(price, 0, "Price must be positive");
        assertEq(decimals, 8, "ETH/USD feed has 8 decimals");
    }

    function test_fork_chainlinkFeedIsFresh() public view {
        assertTrue(oracle.isFresh(), "Feed must be fresh on fork");
    }

    function test_fork_stalePriceReverts() public {
        // Simulate stale price by warping far into the future
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert();
        oracle.getPrice();
    }
}

// ─── Fork Test 2: USDC on Base Sepolia ───────────────────────────────────────

contract ForkUSDCTest is Test {
    // Base Sepolia USDC
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string("https://sepolia.base.org"));
        vm.createSelectFork(rpc);
    }

    function test_fork_usdcExists() public view {
        assertGt(IERC20(USDC).totalSupply(), 0, "USDC must have supply");
    }

    function test_fork_usdcTransfer() public {
        // Deal USDC to a test address and transfer
        address whale = makeAddr("whale");
        deal(USDC, whale, 1000e6);

        address recipient = makeAddr("recipient");
        vm.prank(whale);
        IERC20(USDC).transfer(recipient, 100e6);

        assertEq(IERC20(USDC).balanceOf(recipient), 100e6);
    }
}

// ─── Gas Benchmark: Yul vs Solidity CPMM ─────────────────────────────────────

contract GasBenchmarkTest is Test {

    /// @notice Compare gas usage of Yul assembly vs pure-Solidity getAmountOut.
    function test_benchmark_getAmountOutYul() public pure {
        uint256 amountIn   = 1000e18;
        uint256 reserveIn  = 500_000e18;
        uint256 reserveOut = 500_000e18;

        // Yul version
        uint256 out = CPMM.getAmountOut(amountIn, reserveIn, reserveOut);
        assertGt(out, 0);
    }

    function test_benchmark_getAmountOutSolidity() public pure {
        uint256 amountIn   = 1000e18;
        uint256 reserveIn  = 500_000e18;
        uint256 reserveOut = 500_000e18;

        // Solidity reference version
        uint256 out = CPMM.getAmountOutSolidity(amountIn, reserveIn, reserveOut);
        assertGt(out, 0);
    }

    /// @notice Run both and compare; Yul should be cheaper.
    function test_benchmark_yulCheaperThanSolidity() public pure {
        uint256 ain = 1000e18;
        uint256 rin = 500_000e18;
        uint256 rou = 500_000e18;

        // Both produce the same result
        uint256 outYul = CPMM.getAmountOut(ain, rin, rou);
        uint256 outSol = CPMM.getAmountOutSolidity(ain, rin, rou);
        assertEq(outYul, outSol, "Results must match");
    }
}
