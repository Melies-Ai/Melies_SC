// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../Melies.sol";
import "../MeliesStaking.sol";
import "../MeliesICO.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
