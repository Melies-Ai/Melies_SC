// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    bool public shouldRevert;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        if (shouldRevert) revert("MockERC20: revert");
        _mint(to, amount);
    }

    function setShouldRevert(bool _shouldRevert) public {
        shouldRevert = _shouldRevert;
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        if (shouldRevert) revert("MockERC20: revert");
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        if (shouldRevert) revert("MockERC20: revert");
        return super.transferFrom(from, to, amount);
    }
}
