// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../Melies.sol";
import "../MeliesICO.sol";

contract MockMelies is Melies {
    constructor(
        address defaultAdmin,
        address pauser,
        address minter,
        address burner,
        uint256 initialTgeTimestamp
    ) Melies(defaultAdmin, pauser, minter, burner, initialTgeTimestamp) {}

    function setTgeTimestamp(uint256 newTgeTimestamp) public {
        tgeTimestamp = newTgeTimestamp;
    }
}

contract MockMeliesICO is MeliesICO {
    constructor(
        address _meliesToken,
        address _usdcToken,
        address _usdtToken,
        address _uniswapRouter,
        address _ethUsdPriceFeed,
        uint256 _tgeTimestamp
    )
        MeliesICO(
            _meliesToken,
            _usdcToken,
            _usdtToken,
            _uniswapRouter,
            _ethUsdPriceFeed,
            _tgeTimestamp
        )
    {}

    function setTgeTimestamp(uint256 newTgeTimestamp) public {
        tgeTimestamp = newTgeTimestamp;
    }
}
