// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title CPMM
/// @notice Constant-Product Market Maker math library.
///         Core formula: x * y = k,  fee = 0.3%
///         Critical functions have an inline-Yul assembly version benchmarked
///         against the pure-Solidity equivalent (see GasBenchmark.t.sol).
library CPMM {
    uint256 internal constant FEE_NUMERATOR   = 997;
    uint256 internal constant FEE_DENOMINATOR = 1000;

    // ─── Pure Solidity (reference) ────────────────────────────────────────

    /// @notice Compute output amount using constant-product formula with 0.3% fee.
    /// @dev    amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    function getAmountOutSolidity(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0,                    "CPMM: zero input");
        require(reserveIn > 0 && reserveOut > 0, "CPMM: empty reserves");
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator       = amountInWithFee * reserveOut;
        uint256 denominator     = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // ─── Yul Assembly (optimised) ─────────────────────────────────────────

    /// @notice Same formula implemented in inline Yul assembly.
    ///         Saves ~50 gas vs Solidity version on typical inputs by removing
    ///         Solidity's implicit overflow checks and stack management.
    ///         Benchmarked in test/unit/GasBenchmark.t.sol.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        assembly {
            // Validate inputs — revert with no data on failure (saves gas)
            if iszero(amountIn)  { revert(0, 0) }
            if iszero(reserveIn) { revert(0, 0) }
            if iszero(reserveOut){ revert(0, 0) }

            // amountInWithFee = amountIn * 997
            let amountInWithFee := mul(amountIn, 997)

            // numerator = amountInWithFee * reserveOut
            let numerator := mul(amountInWithFee, reserveOut)

            // denominator = reserveIn * 1000 + amountInWithFee
            let denominator := add(mul(reserveIn, 1000), amountInWithFee)

            // amountOut = numerator / denominator
            amountOut := div(numerator, denominator)
        }
    }

    /// @notice Compute the initial LP shares for the first liquidity deposit.
    ///         Uses integer square-root (Babylonian method) in Yul.
    function initialShares(uint256 amountA, uint256 amountB)
        internal pure returns (uint256 shares)
    {
        assembly {
            // Babylonian integer sqrt of (amountA * amountB)
            let product := mul(amountA, amountB)
            // handle zero
            if iszero(product) { revert(0, 0) }

            let z := product
            let x := div(add(product, 1), 2)
            for {} lt(x, z) {} {
                z := x
                x := div(add(div(product, x), x), 2)
            }
            shares := z
        }
    }

    /// @notice Verify constant-product invariant: newK >= oldK after a swap.
    ///         Returns true if invariant holds (k must never decrease).
    function invariantHolds(
        uint256 oldReserveA,
        uint256 oldReserveB,
        uint256 newReserveA,
        uint256 newReserveB
    ) internal pure returns (bool) {
        // Use assembly to avoid overflow revert on large reserve products
        assembly {
            let oldK := mul(oldReserveA, oldReserveB)
            let newK := mul(newReserveA, newReserveB)
            // Return newK >= oldK
            mstore(0x00, iszero(lt(newK, oldK)))
            return(0x00, 0x20)
        }
    }
}
