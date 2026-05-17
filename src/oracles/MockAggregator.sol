// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockAggregator {
    int256  private _price;
    uint8   private _decimals;
    uint80  private _roundId;
    bool    private _stale;
    uint256 private _stalenessTs;

    constructor(int256 initialPrice, uint8 decimals_) {
        _price    = initialPrice;
        _decimals = decimals_;
        _roundId  = 1;
    }

    function setPrice(int256 price_) external {
        _price = price_;
        _roundId++;
        _stale = false;
    }

    function setUpdatedAt(uint256 ts) external {
        _stale = true;
        _stalenessTs = ts;
    }

    function setRoundId(uint80 id) external { _roundId = id; }
    function decimals() external view returns (uint8) { return _decimals; }

    function latestRoundData()
        external view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        uint256 updatedAt = _stale ? _stalenessTs : block.timestamp;
        return (_roundId, _price, updatedAt, updatedAt, _roundId);
    }
}
