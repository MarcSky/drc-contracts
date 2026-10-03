// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITournamentPool {
    struct Pool {
        uint64 regCloseAt;
        uint64 settleBy;
        uint64 settledAt;
        uint64 sweepAt;
        uint64 canceledAt;
        uint64 ticketCount;
        uint16 poolBps;
        bool swept;
        bool guaranteeWithdrawn;
        bytes32 root;
    }

    struct Leg {
        uint256 ticketPrice;
        uint256 guaranteed;
        uint256 revenue;
        uint256 sponsored;
        uint256 prizeTotal;
        uint256 claimed;
    }

    struct Claim {
        uint256 index;
        address account;
        address token;
        uint256 amount;
        bytes32[] proof;
    }

    event PoolCreated(bytes32 indexed id);
    event TicketBought(bytes32 indexed id, address indexed wallet, address indexed token, uint256 ticketNo);
    event Sponsored(bytes32 indexed id, address indexed sponsor, address indexed token, uint256 amount);
    event Settled(bytes32 indexed id, bytes32 root, address treasury, uint64 sweepAt);
    event LegSettled(bytes32 indexed id, address indexed token, uint256 prizeTotal, uint256 house);
    event Claimed(bytes32 indexed id, uint256 index, address indexed account, address indexed token, uint256 amount);
    event Canceled(bytes32 indexed id, address indexed caller);
    event Refunded(bytes32 indexed id, address indexed wallet, address indexed token, uint256 amount);
    event RefundPushed(bytes32 indexed id, address indexed wallet, address indexed token, uint256 amount);
    event RefundSkipped(bytes32 indexed id, address indexed wallet);
    event GuaranteeWithdrawn(bytes32 indexed id, address indexed owner, address indexed token, uint256 amount);
    event SponsorshipWithdrawn(bytes32 indexed id, address indexed sponsor, address indexed token, uint256 amount);
    event PoolSwept(bytes32 indexed id, address indexed treasury, address indexed token, uint256 amount);
    event ClaimWindowUpdated(uint64 previousWindow, uint64 newWindow);
    event TreasuryAdded(address indexed treasury);
    event TreasuryRemoved(address indexed treasury);
    event TreasuryListSet(uint256 count);
    event SanctionsOracleUpdated(address indexed previousOracle, address indexed newOracle);
    event AllowedTokenSet(address indexed token, bool allowed);

    error PoolExists(bytes32 id);
    error PoolUnknown(bytes32 id);
    error InvalidId();
    error InvalidToken();
    error TokenNotAllowed(address token);
    error TransferShortfall(address token, uint256 expected, uint256 received);
    error InvalidTokenList();
    error DuplicateToken(address token);
    error TokenNotInPool(bytes32 id, address token);
    error InvalidTicketPrice();
    error InvalidPoolBps(uint16 poolBps);
    error InvalidSchedule();
    error InvalidClaimWindow();
    error InvalidValue(uint256 expected, uint256 given);
    error RegistrationClosed(bytes32 id);
    error RegistrationOpen(bytes32 id);
    error AlreadyHasTicket(bytes32 id, address wallet);
    error NoTicket(bytes32 id, address wallet);
    error AlreadySettled(bytes32 id);
    error NotSettled(bytes32 id);
    error PoolCanceled(bytes32 id);
    error PoolNotCanceled(bytes32 id);
    error CancelWindowOpen(bytes32 id);
    error RefundWindowOpen(bytes32 id);
    error PrizeTotalMismatch(address token, uint256 fund, uint256 given);
    error InvalidRoot();
    error AlreadyClaimed(bytes32 id, uint256 index);
    error InvalidProof();
    error ClaimExceedsPool();
    error SweepWindowOpen(bytes32 id);
    error AlreadySwept(bytes32 id);
    error NothingToWithdraw();
    error NativeTransferFailed(address to, uint256 amount);
    error BatchTooLarge(uint256 size, uint256 limit);
    error InvalidTreasury();
    error DuplicateTreasury(address treasury);
    error TreasuryNotFound(address treasury);
    error CannotRemoveLastTreasury();
    error EmptyTreasuryList();
    error SanctionedAddress(address wallet);

    function create(
        bytes32 id,
        address[] calldata tokens,
        uint256[] calldata ticketPrices,
        uint16 poolBps,
        uint256[] calldata guaranteed,
        uint64 regCloseAt,
        uint64 settleBy
    ) external payable;

    function buyTicket(bytes32 id, address token) external payable;
    function sponsor(bytes32 id, address token, uint256 amount) external payable;
    function settle(bytes32 id, bytes32 root, uint256[] calldata prizeTotals) external;
    function claim(bytes32 id, uint256 index, address account, address token, uint256 amount, bytes32[] calldata proof)
        external;
    function claimMany(bytes32 id, Claim[] calldata claims) external;
    function cancel(bytes32 id) external;
    function refund(bytes32 id) external;
    function refundUnclaimed(bytes32 id, address[] calldata wallets) external;
    function withdrawGuarantee(bytes32 id) external;
    function withdrawSponsorship(bytes32 id, address token) external;
    function sweep(bytes32 id) external;
    function setAllowedToken(address token, bool allowed) external;

    function getPool(bytes32 id) external view returns (Pool memory);
    function getLeg(bytes32 id, address token) external view returns (Leg memory);
    function getPoolTokens(bytes32 id) external view returns (address[] memory);
    function fundOf(bytes32 id, address token) external view returns (uint256);
    function ticketToken(bytes32 id, address wallet) external view returns (address);
    function isClaimed(bytes32 id, uint256 index) external view returns (bool);
    function allowedToken(address token) external view returns (bool);
}
