// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PredictionMarketV1} from "./PredictionMarketV1.sol";

contract PredictionMarketV2 is PredictionMarketV1 {

    uint256 public referencePrice;
    uint8   public referenceDecimals;

    event OracleSnapshotTaken(uint256 price, uint8 decimals, uint256 timestamp);

    function resolveMarket(uint256 winningId)
        external
        virtual
        override
        onlyRole(RESOLVER_ROLE)
        inState(MarketState.Closed)
    {
        if (winningId != YES_ID && winningId != NO_ID) revert InvalidOutcome(winningId);
        if (!oracle.isFresh()) revert NotYetResolvable();

        (uint256 price, uint8 dec) = oracle.getPrice();
        referencePrice    = price;
        referenceDecimals = dec;
        emit OracleSnapshotTaken(price, dec, block.timestamp);

        winningOutcome = winningId == YES_ID ? Outcome.YES : Outcome.NO;
        resolvedAt     = block.timestamp;
        state          = MarketState.Resolved;

        emit MarketResolved(winningOutcome, resolvedAt);
    }

    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}