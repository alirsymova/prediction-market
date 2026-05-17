// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20}       from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes}  from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable}     from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces}      from "@openzeppelin/contracts/utils/Nonces.sol";

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {

    uint256 public constant INITIAL_SUPPLY = 10_000_000e18;

    constructor(address initialOwner)
        ERC20("PredMarket Token", "PMT")
        ERC20Permit("PredMarket Token")
        Ownable(initialOwner)
    {
        _mint(initialOwner, INITIAL_SUPPLY);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 amount)
        internal override(ERC20, ERC20Votes)
    {
        super._update(from, to, amount);
    }

    function nonces(address owner)
        public view override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}