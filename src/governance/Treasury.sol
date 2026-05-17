// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20}        from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Treasury
/// @notice Protocol treasury controlled exclusively by the Timelock (DAO).
///         Holds protocol fees and governance token reserves.
///
/// @dev    Adapted from Assignment 4 Treasury.sol.
///         Only EXECUTOR_ROLE (= Timelock) can withdraw funds.
///         No admin backdoor — DEFAULT_ADMIN_ROLE is renounced after setup.
contract Treasury is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    event Received(address indexed from, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);

    error WithdrawFailed();
    error ZeroAddress();
    error ZeroAmount();

    constructor(address timelock) {
        if (timelock == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, timelock);
        _grantRole(EXECUTOR_ROLE,      timelock);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Withdraw ERC-20 tokens. Only callable by Timelock after DAO vote.
    function withdrawERC20(address token, address to, uint256 amount)
        external onlyRole(EXECUTOR_ROLE)
    {
        if (to     == address(0)) revert ZeroAddress();
        if (amount == 0)          revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Withdrawn(token, to, amount);
    }

    /// @notice Withdraw ETH. Only callable by Timelock.
    function withdrawETH(address payable to, uint256 amount)
        external onlyRole(EXECUTOR_ROLE)
    {
        if (to     == address(0)) revert ZeroAddress();
        if (amount == 0)          revert ZeroAmount();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
        emit ETHWithdrawn(to, amount);
    }

    function ethBalance() external view returns (uint256) { return address(this).balance; }
    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
