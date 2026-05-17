// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracleAdapter, AggregatorV3Interface} from "../interfaces/IInterfaces.sol";

/// @title ChainlinkAdapter
/// @notice Wraps Chainlink AggregatorV3Interface with staleness check.
///         Implements IOracleAdapter — oracle abstraction pattern.
/// @dev    Adapted from Assignment 3 PriceFeedConsumer with interface abstraction layer added.
contract ChainlinkAdapter is IOracleAdapter {
    AggregatorV3Interface public immutable feed;

    /// @notice Maximum age of a price before it is considered stale (1 hour).
    uint256 public immutable stalenessThreshold;

    event PriceFetched(int256 price, uint256 updatedAt);

    error StalePrice(uint256 updatedAt, uint256 threshold);
    error NonPositivePrice(int256 price);
    error IncompleteRound();

    constructor(address _feed, uint256 _stalenessThreshold) {
        require(_feed != address(0), "ChainlinkAdapter: zero feed");
        feed = AggregatorV3Interface(_feed);
        stalenessThreshold = _stalenessThreshold == 0 ? 1 hours : _stalenessThreshold;
    }

    /// @inheritdoc IOracleAdapter
    function getPrice() external view override returns (uint256 price, uint8 decimals) {
        (
            uint80  roundId,
            int256  answer,
            ,
            uint256 updatedAt,
            uint80  answeredInRound
        ) = feed.latestRoundData();

        if (updatedAt == 0) revert IncompleteRound();
        if (answeredInRound < roundId) revert StalePrice(updatedAt, stalenessThreshold);
        if (block.timestamp - updatedAt > stalenessThreshold)
            revert StalePrice(updatedAt, stalenessThreshold);
        if (answer <= 0) revert NonPositivePrice(answer);

        price    = uint256(answer);
        decimals = feed.decimals();
    }

    /// @inheritdoc IOracleAdapter
    function isFresh() external view override returns (bool) {
        try feed.latestRoundData() returns (
            uint80, int256 answer, uint256, uint256 updatedAt, uint80
        ) {
            return answer > 0 && block.timestamp - updatedAt <= stalenessThreshold;
        } catch {
            return false;
        }
    }
}
