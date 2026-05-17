// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable}       from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable}         from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable}   from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC1155Upgradeable}    from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {IERC20}                from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}             from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CPMM}          from "../libraries/CPMM.sol";
import {IOracleAdapter} from "../interfaces/IInterfaces.sol";
import {IFeeVault}      from "../interfaces/IInterfaces.sol";
import {IPredictionMarket} from "../interfaces/IInterfaces.sol";

contract PredictionMarketV1 is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC1155SupplyUpgradeable,
    IPredictionMarket
{
    using SafeERC20 for IERC20;
    using CPMM      for uint256;

    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public constant YES_ID = 1;
    uint256 public constant NO_ID  = 2;

    MarketState public state;

    string       public question;
    uint256      public resolutionTime;
    uint256      public disputeWindow;
    IOracleAdapter public oracle;
    IERC20         public collateral;
    IFeeVault      public feeVault;

    uint256 public reserveYES;
    uint256 public reserveNO;

    Outcome    public winningOutcome;
    uint256    public resolvedAt;
    uint256    public totalCollateral;

    uint256 public totalLPShares;
    mapping(address => uint256) public lpShares;

    mapping(address => bool) public hasClaimed;

    uint256[42] private __gap;

    event SharesBought(address indexed buyer, uint256 outcomeId, uint256 amountIn, uint256 sharesOut);
    event SharesSold(address indexed seller, uint256 outcomeId, uint256 sharesIn, uint256 amountOut);
    event MarketClosed(uint256 timestamp);
    event MarketResolved(Outcome outcome, uint256 resolvedAt);
    event MarketDisputed(address indexed disputer);
    event MarketSettled();
    event WinningsClaimed(address indexed claimer, uint256 payout);
    event LiquidityAdded(address indexed provider, uint256 amountYES, uint256 amountNO, uint256 shares);
    event LiquidityRemoved(address indexed provider, uint256 shares, uint256 amountYES, uint256 amountNO);

    error WrongState(MarketState current, MarketState expected);
    error SlippageExceeded(uint256 got, uint256 minimum);
    error InvalidOutcome(uint256 id);
    error ResolutionTooEarly();
    error DisputeWindowActive();
    error AlreadyClaimed();
    error NothingToClaim();
    error ZeroAmount();
    error NotYetResolvable();

    modifier inState(MarketState s) {
        if (state != s) revert WrongState(state, s);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(
        string  calldata _question,
        uint256 _resolutionTime,
        uint256 _disputeWindow,
        address _oracle,
        address _collateral,
        address _feeVault,
        address _admin,
        uint256 _initialLiquidity
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC1155_init("https://api.predmarket.xyz/metadata/{id}.json");

        question       = _question;
        resolutionTime = _resolutionTime;
        disputeWindow  = _disputeWindow == 0 ? 1 days : _disputeWindow;
        oracle         = IOracleAdapter(_oracle);
        collateral     = IERC20(_collateral);
        feeVault       = IFeeVault(_feeVault);
        state          = MarketState.Open;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(RESOLVER_ROLE,      _admin);
        _grantRole(PAUSER_ROLE,        _admin);
        _grantRole(UPGRADER_ROLE,      _admin);

        if (_initialLiquidity > 0) {
            uint256 half = _initialLiquidity / 2;
            reserveYES = half;
            reserveNO  = half;
            totalCollateral = _initialLiquidity;

            uint256 shares = CPMM.initialShares(half, half);
            totalLPShares       += shares;
            lpShares[_admin]    += shares;

            collateral.safeTransferFrom(msg.sender, address(this), _initialLiquidity);
            emit LiquidityAdded(_admin, half, half, shares);
        }
    }

    function buyShares(
        uint256 outcomeId,
        uint256 amountIn,
        uint256 minSharesOut
    ) external override nonReentrant whenNotPaused inState(MarketState.Open) returns (uint256 sharesOut) {
        if (outcomeId != YES_ID && outcomeId != NO_ID) revert InvalidOutcome(outcomeId);
        if (amountIn == 0) revert ZeroAmount();

        (uint256 reserveIn, uint256 reserveOut) = outcomeId == YES_ID
            ? (reserveNO, reserveYES)
            : (reserveYES, reserveNO);

        sharesOut = CPMM.getAmountOut(amountIn, reserveIn, reserveOut);
        if (sharesOut < minSharesOut) revert SlippageExceeded(sharesOut, minSharesOut);

        uint256 fee = amountIn * 3 / 1000;
        if (outcomeId == YES_ID) {
            reserveNO  += (amountIn - fee);
            reserveYES -= sharesOut;
        } else {
            reserveYES += (amountIn - fee);
            reserveNO  -= sharesOut;
        }
        totalCollateral += amountIn;

        collateral.safeTransferFrom(msg.sender, address(this), amountIn);
        if (fee > 0) {
            IERC20(address(collateral)).forceApprove(address(feeVault), fee);
            feeVault.depositFee(fee);
        }
        _mint(msg.sender, outcomeId, sharesOut, "");

        emit SharesBought(msg.sender, outcomeId, amountIn, sharesOut);
    }

    function sellShares(
        uint256 outcomeId,
        uint256 sharesIn,
        uint256 minAmountOut
    ) external override nonReentrant whenNotPaused inState(MarketState.Open) returns (uint256 amountOut) {
        if (outcomeId != YES_ID && outcomeId != NO_ID) revert InvalidOutcome(outcomeId);
        if (sharesIn == 0) revert ZeroAmount();

        (uint256 reserveIn, uint256 reserveOut) = outcomeId == YES_ID
            ? (reserveYES, reserveNO)
            : (reserveNO, reserveYES);

        amountOut = CPMM.getAmountOut(sharesIn, reserveIn, reserveOut);
        if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);

        uint256 fee = amountOut * 3 / 1000;
        amountOut -= fee;

        if (outcomeId == YES_ID) {
            reserveYES += sharesIn;
            reserveNO  -= (amountOut + fee);
        } else {
            reserveNO  += sharesIn;
            reserveYES -= (amountOut + fee);
        }
        totalCollateral -= amountOut;

        _burn(msg.sender, outcomeId, sharesIn);
        IERC20(address(collateral)).forceApprove(address(feeVault), fee);
        feeVault.depositFee(fee);
        collateral.safeTransfer(msg.sender, amountOut);

        emit SharesSold(msg.sender, outcomeId, sharesIn, amountOut);
    }

    function closeMarket() external inState(MarketState.Open) {
        if (block.timestamp < resolutionTime) revert ResolutionTooEarly();
        state = MarketState.Closed;
        emit MarketClosed(block.timestamp);
    }

    function resolveMarket(uint256 winningId)
        external virtual override
        onlyRole(RESOLVER_ROLE)
        inState(MarketState.Closed)
    {
        if (winningId != YES_ID && winningId != NO_ID) revert InvalidOutcome(winningId);
        if (!oracle.isFresh()) revert NotYetResolvable();

        winningOutcome = winningId == YES_ID ? Outcome.YES : Outcome.NO;
        resolvedAt     = block.timestamp;
        state          = MarketState.Resolved;

        emit MarketResolved(winningOutcome, resolvedAt);
    }

    function disputeResolution() external inState(MarketState.Resolved) {
        if (block.timestamp > resolvedAt + disputeWindow) revert DisputeWindowActive();
        state = MarketState.Disputed;
        emit MarketDisputed(msg.sender);
    }

    function resolveDispute(uint256 winningId)
        external
        onlyRole(RESOLVER_ROLE)
        inState(MarketState.Disputed)
    {
        if (winningId != YES_ID && winningId != NO_ID) revert InvalidOutcome(winningId);
        winningOutcome = winningId == YES_ID ? Outcome.YES : Outcome.NO;
        resolvedAt     = block.timestamp;
        state          = MarketState.Resolved;
        emit MarketResolved(winningOutcome, resolvedAt);
    }

    function settleMarket() external inState(MarketState.Resolved) {
        if (block.timestamp < resolvedAt + disputeWindow) revert DisputeWindowActive();
        state = MarketState.Settled;
        emit MarketSettled();
    }

    function claimWinnings()
        external override
        nonReentrant
        inState(MarketState.Settled)
        returns (uint256 payout)
    {
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        uint256 winId  = winningOutcome == Outcome.YES ? YES_ID : NO_ID;
        uint256 shares = balanceOf(msg.sender, winId);
        if (shares == 0) revert NothingToClaim();

        uint256 winningReserve = winningOutcome == Outcome.YES ? reserveYES : reserveNO;
        uint256 totalWinShares = totalSupply(winId);

        hasClaimed[msg.sender] = true;
        payout = totalWinShares == 0 ? 0 : (shares * winningReserve) / totalWinShares;

        _burn(msg.sender, winId, shares);
        collateral.safeTransfer(msg.sender, payout);

        emit WinningsClaimed(msg.sender, payout);
    }

    function addLiquidity(uint256 amountYES, uint256 amountNO)
        external
        nonReentrant
        whenNotPaused
        inState(MarketState.Open)
    {
        if (amountYES == 0 || amountNO == 0) revert ZeroAmount();

        uint256 shares;
        if (totalLPShares == 0) {
            shares = CPMM.initialShares(amountYES, amountNO);
        } else {
            uint256 sharesYES = (amountYES * totalLPShares) / reserveYES;
            uint256 sharesNO  = (amountNO  * totalLPShares) / reserveNO;
            shares = sharesYES < sharesNO ? sharesYES : sharesNO;
        }

        reserveYES      += amountYES;
        reserveNO       += amountNO;
        totalCollateral += amountYES + amountNO;
        totalLPShares   += shares;
        lpShares[msg.sender] += shares;

        collateral.safeTransferFrom(msg.sender, address(this), amountYES + amountNO);
        emit LiquidityAdded(msg.sender, amountYES, amountNO, shares);
    }

    function removeLiquidity(uint256 shares)
        external
        nonReentrant
        inState(MarketState.Open)
    {
        if (shares == 0) revert ZeroAmount();
        require(lpShares[msg.sender] >= shares, "PredictionMarket: insufficient LP shares");

        uint256 amountYES = (shares * reserveYES) / totalLPShares;
        uint256 amountNO  = (shares * reserveNO)  / totalLPShares;

        lpShares[msg.sender] -= shares;
        totalLPShares        -= shares;
        reserveYES           -= amountYES;
        reserveNO            -= amountNO;
        totalCollateral      -= (amountYES + amountNO);

        collateral.safeTransfer(msg.sender, amountYES + amountNO);
        emit LiquidityRemoved(msg.sender, shares, amountYES, amountNO);
    }

    function getReserves() external view override returns (uint256, uint256) {
        return (reserveYES, reserveNO);
    }

    function getMarketInfo() external view override returns (
        string memory, uint256, MarketState, Outcome
    ) {
        return (question, resolutionTime, state, winningOutcome);
    }

    function impliedProbabilityYES() external view returns (uint256) {
        uint256 total = reserveYES + reserveNO;
        if (total == 0) return 5e17;
        return (reserveNO * 1e18) / total;
    }

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function supportsInterface(bytes4 interfaceId)
        public view virtual override(AccessControlUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal override(ERC1155SupplyUpgradeable)
    {
        super._update(from, to, ids, values);
    }

    function _authorizeUpgrade(address newImpl)
        internal override onlyRole(UPGRADER_ROLE) {}
}