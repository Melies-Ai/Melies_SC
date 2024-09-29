// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";

contract MockChainlinkAggregator is AggregatorV3Interface {
    int256 private _answer;
    uint8 private _decimals;
    uint256 private _version;
    string private _description;

    constructor() {
        _answer = 0;
        _decimals = 8;
        _version = 1;
        _description = "Mock ETH/USD Price Feed";
    }

    function updateAnswer(int256 _newAnswer) external {
        if (_newAnswer != 0) {
            _answer = (1e18 / _newAnswer);
        } else {
            _answer = 0;
        }
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _answer, block.timestamp, block.timestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, _answer, block.timestamp, block.timestamp, 0);
    }
}
