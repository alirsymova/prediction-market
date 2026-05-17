// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IFeeVault} from "../interfaces/IInterfaces.sol";

contract FeeVault is ERC4626, AccessControl, IFeeVault {
    using SafeERC20 for IERC20;

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    uint256 private _totalFeesCollected;

    event FeeDeposited(address indexed from, uint256 amount);
    event FeeWithdrawn(address indexed to,   uint256 amount);

    error NotDepositor();
    error ZeroAmount();

    constructor(IERC20 asset_, address admin)
        ERC4626(asset_)
        ERC20("FeeVault Share", "FVS")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function depositFee(uint256 amount) external override onlyRole(DEPOSITOR_ROLE) {
        if (amount == 0) revert ZeroAmount();
        _totalFeesCollected += amount;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit FeeDeposited(msg.sender, amount);
    }

    function totalFeesCollected() external view override returns (uint256) {
        return _totalFeesCollected;
    }
}