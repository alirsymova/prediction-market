// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ─── Chainlink ────────────────────────────────────────────────────────────────
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

// ─── Oracle Adapter ───────────────────────────────────────────────────────────
interface IOracleAdapter {
    function getPrice() external view returns (uint256 price, uint8 decimals);
    function isFresh() external view returns (bool);
}

// ─── Prediction Market ────────────────────────────────────────────────────────
interface IPredictionMarket {

    enum MarketState {
        Open,
        Closed,
        Resolved,
        Disputed,
        Settled
    }

    enum Outcome {
        YES,
        NO
    }

    function buyShares(
        uint256 outcomeId,
        uint256 amountIn,
        uint256 minSharesOut
    ) external returns (uint256 sharesOut);

    function sellShares(
        uint256 outcomeId,
        uint256 sharesIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    function resolveMarket(uint256 winningOutcome) external;

    function claimWinnings() external returns (uint256 payout);

    function getReserves()
        external
        view
        returns (uint256 reserveYES, uint256 reserveNO);

    function getMarketInfo()
        external
        view
        returns (
            string memory question,
            uint256 resolutionTime,
            MarketState state,
            Outcome outcome
        );
}

// ─── Fee Vault ────────────────────────────────────────────────────────────────
interface IFeeVault {
    function depositFee(uint256 amount) external;
    function totalFeesCollected() external view returns (uint256);
}

// ─── Factory ──────────────────────────────────────────────────────────────────
interface IMarketFactory {
    function createMarket(
        string calldata question,
        uint256 resolutionTime,
        address oracle,
        uint256 initialLiquidity
    ) external returns (address market);

    function getMarkets() external view returns (address[] memory);

    function isMarket(address addr) external view returns (bool);
}