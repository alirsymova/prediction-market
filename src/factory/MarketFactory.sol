// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMarketFactory} from "../interfaces/IInterfaces.sol";
import {PredictionMarketV1} from "../core/PredictionMarketV1.sol";

/// @title MarketFactory
/// @notice Deploys PredictionMarket proxies using both CREATE and CREATE2.
///
/// @dev    Design patterns:
///         - Factory pattern  (contract deployment abstraction)
///         - AccessControl    (only CREATOR_ROLE can deploy markets)
///         - CREATE2          (deterministic market addresses for frontend pre-computation)
///         - CREATE           (standard deployment when determinism not needed)
///
/// @dev    Adapted from Assignment 1 Factory.sol — upgraded to deploy
///         UUPS proxies and register markets in an indexed registry.
contract MarketFactory is AccessControl, IMarketFactory {

    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    /// @notice The singleton logic contract used as UUPS implementation.
    address public immutable implementation;

    /// @notice Default collateral token for all markets.
    address public immutable collateral;

    /// @notice Shared FeeVault address.
    address public immutable feeVault;

    /// @notice Default oracle staleness + dispute window.
    uint256 public defaultDisputeWindow;

    address[] private _markets;
    mapping(address => bool) private _isMarket;

    // CREATE2 salt → market address
    mapping(bytes32 => address) public marketBySalt;

    event MarketCreated(
        address indexed market,
        string  question,
        address oracle,
        uint256 resolutionTime,
        bytes32 salt,
        bool    deterministic
    );

    error SaltAlreadyUsed(bytes32 salt);
    error ZeroAddress();

    constructor(
        address _implementation,
        address _collateral,
        address _feeVault,
        address _admin
    ) {
        if (_implementation == address(0)) revert ZeroAddress();
        if (_collateral     == address(0)) revert ZeroAddress();
        if (_feeVault       == address(0)) revert ZeroAddress();

        implementation       = _implementation;
        collateral           = _collateral;
        feeVault             = _feeVault;
        defaultDisputeWindow = 1 days;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CREATOR_ROLE,       _admin);
    }

    // ─── IMarketFactory ───────────────────────────────────────────────────

    /// @notice Deploy a market via standard CREATE (non-deterministic address).
    function createMarket(
        string  calldata question,
        uint256 resolutionTime,
        address oracle,
        uint256 initialLiquidity
    ) external override onlyRole(CREATOR_ROLE) returns (address market) {
        market = _deployProxy(question, resolutionTime, oracle, initialLiquidity);
        emit MarketCreated(market, question, oracle, resolutionTime, bytes32(0), false);
    }

    /// @notice Deploy a market via CREATE2 (deterministic address from salt).
    /// @param  salt   Arbitrary bytes32 chosen by caller. Must be unique.
    function createMarketDeterministic(
        string  calldata question,
        uint256 resolutionTime,
        address oracle,
        uint256 initialLiquidity,
        bytes32 salt
    ) external onlyRole(CREATOR_ROLE) returns (address market) {
        if (marketBySalt[salt] != address(0)) revert SaltAlreadyUsed(salt);

        bytes memory initCode = _proxyInitCode(question, resolutionTime, oracle, initialLiquidity);

        assembly {
            market := create2(0, add(initCode, 0x20), mload(initCode), salt)
            if iszero(extcodesize(market)) { revert(0, 0) }
        }

        marketBySalt[salt] = market;
        _markets.push(market);
        _isMarket[market] = true;

        emit MarketCreated(market, question, oracle, resolutionTime, salt, true);
    }

    /// @notice Pre-compute the CREATE2 address without deploying.
    function computeAddress(bytes32 salt, string calldata question, uint256 resolutionTime, address oracle, uint256 initialLiquidity)
        external view returns (address predicted)
    {
        bytes32 initCodeHash = keccak256(_proxyInitCode(question, resolutionTime, oracle, initialLiquidity));
        predicted = address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)
        ))));
    }

    function getMarkets() external view override returns (address[] memory) {
        return _markets;
    }

    function isMarket(address addr) external view override returns (bool) {
        return _isMarket[addr];
    }

    function marketCount() external view returns (uint256) {
        return _markets.length;
    }

    // ─── Internal ─────────────────────────────────────────────────────────

    function _deployProxy(
        string  calldata question,
        uint256 resolutionTime,
        address oracle,
        uint256 initialLiquidity
    ) internal returns (address market) {
        bytes memory initData = _encodeInit(question, resolutionTime, oracle, initialLiquidity);
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
        market = address(proxy);
        _markets.push(market);
        _isMarket[market] = true;
    }

    function _proxyInitCode(
        string  calldata question,
        uint256 resolutionTime,
        address oracle,
        uint256 initialLiquidity
    ) internal view returns (bytes memory) {
        bytes memory initData = _encodeInit(question, resolutionTime, oracle, initialLiquidity);
        return abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );
    }

    function _encodeInit(
        string  calldata question,
        uint256 resolutionTime,
        address oracle,
        uint256 initialLiquidity
    ) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            PredictionMarketV1.initialize.selector,
            question,
            resolutionTime,
            defaultDisputeWindow,
            oracle,
            collateral,
            feeVault,
            msg.sender,
            initialLiquidity
        );
    }

    function setDefaultDisputeWindow(uint256 window) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultDisputeWindow = window;
    }
}
