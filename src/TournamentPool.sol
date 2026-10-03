// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITournamentPool} from "./interfaces/ITournamentPool.sol";
import {ISanctionsOracle} from "./interfaces/ISanctionsOracle.sol";

contract TournamentPool is ITournamentPool, Ownable2Step, Pausable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    address public constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint16 public constant MIN_POOL_BPS = 2500;
    uint16 public constant MAX_POOL_BPS = 10_000;
    uint256 public constant MAX_TOKENS = 3;
    uint256 public constant MAX_REFUND_BATCH = 200;
    uint256 public constant REFUND_PUSH_GAS = 50_000;
    uint64 public constant CANCEL_GRACE = 7 days;
    uint64 public constant REFUND_WINDOW = 30 days;
    uint64 public constant MIN_CLAIM_WINDOW = 7 days;
    uint64 public constant MAX_CLAIM_WINDOW = 365 days;

    mapping(bytes32 id => Pool) private pools;
    mapping(bytes32 id => address[]) private poolTokens;
    mapping(bytes32 id => mapping(address token => Leg)) private legs;
    mapping(bytes32 id => mapping(address token => bool)) public isPoolToken;
    mapping(bytes32 id => mapping(address wallet => address)) public ticketToken;
    mapping(bytes32 id => mapping(address wallet => bool)) public refunded;
    mapping(bytes32 id => mapping(address token => mapping(address sponsor => uint256))) public sponsorOf;
    mapping(bytes32 id => mapping(uint256 word => uint256)) private claimedBitmap;
    mapping(address token => bool) public allowedToken;

    address[] public treasuries;
    mapping(address treasury => bool) public isTreasury;
    uint256 public treasuryCursor;

    address public sanctionsOracle;
    uint64 public claimWindow;

    constructor(address initialOwner, address[] memory initialTreasuries, uint64 initialClaimWindow)
        Ownable(initialOwner)
    {
        _setTreasuryList(initialTreasuries);
        if (initialClaimWindow < MIN_CLAIM_WINDOW || initialClaimWindow > MAX_CLAIM_WINDOW) {
            revert InvalidClaimWindow();
        }
        claimWindow = initialClaimWindow;
        emit ClaimWindowUpdated(0, initialClaimWindow);
    }

    function create(
        bytes32 id,
        address[] calldata tokens,
        uint256[] calldata ticketPrices,
        uint16 poolBps,
        uint256[] calldata guaranteed,
        uint64 regCloseAt,
        uint64 settleBy
    ) external payable onlyOwner nonReentrant {
        if (id == bytes32(0)) revert InvalidId();
        if (pools[id].regCloseAt != 0) revert PoolExists(id);
        uint256 n = tokens.length;
        if (n == 0 || n > MAX_TOKENS || ticketPrices.length != n || guaranteed.length != n) revert InvalidTokenList();
        if (poolBps < MIN_POOL_BPS || poolBps > MAX_POOL_BPS) revert InvalidPoolBps(poolBps);
        if (regCloseAt <= block.timestamp || settleBy <= regCloseAt) revert InvalidSchedule();

        Pool storage p = pools[id];
        p.poolBps = poolBps;
        p.regCloseAt = regCloseAt;
        p.settleBy = settleBy;

        uint256 nativeGuarantee = _registerTokens(id, tokens, ticketPrices, guaranteed);
        if (msg.value != nativeGuarantee) revert InvalidValue(nativeGuarantee, msg.value);

        emit PoolCreated(id);

        _pullGuarantees(tokens, guaranteed);
    }

    function buyTicket(bytes32 id, address token) external payable whenNotPaused nonReentrant {
        Pool storage p = _open(id);
        if (block.timestamp >= p.regCloseAt) revert RegistrationClosed(id);
        if (!isPoolToken[id][token]) revert TokenNotInPool(id, token);
        if (ticketToken[id][msg.sender] != address(0)) revert AlreadyHasTicket(id, msg.sender);
        _requireNotSanctioned(msg.sender);

        Leg storage leg = legs[id][token];
        uint256 price = leg.ticketPrice;
        _requireValue(token, price);

        ticketToken[id][msg.sender] = token;
        p.ticketCount += 1;
        leg.revenue += price;

        emit TicketBought(id, msg.sender, token, p.ticketCount);

        _pull(token, price);
    }

    function sponsor(bytes32 id, address token, uint256 amount) external payable whenNotPaused nonReentrant {
        _open(id);
        if (!isPoolToken[id][token]) revert TokenNotInPool(id, token);
        if (amount == 0) revert NothingToWithdraw();
        _requireValue(token, amount);

        legs[id][token].sponsored += amount;
        sponsorOf[id][token][msg.sender] += amount;

        emit Sponsored(id, msg.sender, token, amount);

        _pull(token, amount);
    }

    function settle(bytes32 id, bytes32 root, uint256[] calldata prizeTotals) external onlyOwner nonReentrant {
        Pool storage p = _open(id);
        if (block.timestamp < p.regCloseAt) revert RegistrationOpen(id);
        if (root == bytes32(0)) revert InvalidRoot();

        address[] storage tokens = poolTokens[id];
        uint256 n = tokens.length;
        if (prizeTotals.length != n) revert InvalidTokenList();

        p.root = root;
        p.settledAt = uint64(block.timestamp);
        p.sweepAt = uint64(block.timestamp) + claimWindow;

        address dest = _nextTreasury();
        emit Settled(id, root, dest, p.sweepAt);

        uint256[] memory houses = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            Leg storage leg = legs[id][tokens[i]];
            uint256 fund = _fund(leg, p.poolBps);
            if (prizeTotals[i] > fund) revert PrizeTotalMismatch(tokens[i], fund, prizeTotals[i]);

            leg.prizeTotal = prizeTotals[i];
            houses[i] = leg.guaranteed + leg.revenue + leg.sponsored - prizeTotals[i];
            emit LegSettled(id, tokens[i], prizeTotals[i], houses[i]);
        }

        for (uint256 i = 0; i < n; ++i) {
            if (houses[i] > 0) _push(tokens[i], dest, houses[i]);
        }
    }

    function claim(bytes32 id, uint256 index, address account, address token, uint256 amount, bytes32[] calldata proof)
        external
        nonReentrant
    {
        _claim(id, index, account, token, amount, proof);
    }

    function claimMany(bytes32 id, Claim[] calldata claims) external nonReentrant {
        for (uint256 i = 0; i < claims.length; ++i) {
            Claim calldata c = claims[i];
            _claim(id, c.index, c.account, c.token, c.amount, c.proof);
        }
    }

    function cancel(bytes32 id) external {
        Pool storage p = _open(id);
        if (msg.sender != owner() && block.timestamp < uint256(p.settleBy) + CANCEL_GRACE) {
            revert CancelWindowOpen(id);
        }

        p.canceledAt = uint64(block.timestamp);
        emit Canceled(id, msg.sender);
    }

    function refund(bytes32 id) external nonReentrant {
        _canceled(id);
        address token = ticketToken[id][msg.sender];
        if (token == address(0) || refunded[id][msg.sender]) revert NoTicket(id, msg.sender);

        Leg storage leg = legs[id][token];
        uint256 price = leg.ticketPrice;
        refunded[id][msg.sender] = true;
        leg.revenue -= price;

        emit Refunded(id, msg.sender, token, price);

        _push(token, msg.sender, price);
    }

    function refundUnclaimed(bytes32 id, address[] calldata wallets) external onlyOwner nonReentrant {
        Pool storage p = _canceled(id);
        if (block.timestamp < uint256(p.canceledAt) + REFUND_WINDOW) revert RefundWindowOpen(id);
        if (wallets.length > MAX_REFUND_BATCH) revert BatchTooLarge(wallets.length, MAX_REFUND_BATCH);

        for (uint256 i = 0; i < wallets.length; ++i) {
            address wallet = wallets[i];
            address token = ticketToken[id][wallet];
            if (token == address(0) || refunded[id][wallet]) continue;

            Leg storage leg = legs[id][token];
            uint256 price = leg.ticketPrice;
            refunded[id][wallet] = true;
            leg.revenue -= price;

            if (_tryPush(token, wallet, price)) {
                emit RefundPushed(id, wallet, token, price);
            } else {
                refunded[id][wallet] = false;
                leg.revenue += price;
                emit RefundSkipped(id, wallet);
            }
        }
    }

    function withdrawGuarantee(bytes32 id) external nonReentrant {
        Pool storage p = _canceled(id);
        if (p.guaranteeWithdrawn) revert NothingToWithdraw();
        p.guaranteeWithdrawn = true;

        address to = owner();
        address[] storage tokens = poolTokens[id];
        uint256 n = tokens.length;
        uint256[] memory amounts = new uint256[](n);
        bool any;
        for (uint256 i = 0; i < n; ++i) {
            amounts[i] = legs[id][tokens[i]].guaranteed;
            if (amounts[i] > 0) {
                any = true;
                emit GuaranteeWithdrawn(id, to, tokens[i], amounts[i]);
            }
        }
        if (!any) revert NothingToWithdraw();

        for (uint256 i = 0; i < n; ++i) {
            if (amounts[i] > 0) _push(tokens[i], to, amounts[i]);
        }
    }

    function withdrawSponsorship(bytes32 id, address token) external nonReentrant {
        _canceled(id);
        uint256 amount = sponsorOf[id][token][msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        sponsorOf[id][token][msg.sender] = 0;
        legs[id][token].sponsored -= amount;

        emit SponsorshipWithdrawn(id, msg.sender, token, amount);

        _push(token, msg.sender, amount);
    }

    function sweep(bytes32 id) external onlyOwner nonReentrant {
        Pool storage p = pools[id];
        if (p.regCloseAt == 0) revert PoolUnknown(id);
        if (p.settledAt == 0) revert NotSettled(id);
        if (p.swept) revert AlreadySwept(id);
        if (block.timestamp < p.sweepAt) revert SweepWindowOpen(id);

        p.swept = true;
        address dest = _nextTreasury();

        address[] storage tokens = poolTokens[id];
        uint256 n = tokens.length;
        uint256[] memory amounts = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            Leg storage leg = legs[id][tokens[i]];
            amounts[i] = leg.prizeTotal - leg.claimed;
            leg.claimed = leg.prizeTotal;
            emit PoolSwept(id, dest, tokens[i], amounts[i]);
        }

        for (uint256 i = 0; i < n; ++i) {
            if (amounts[i] > 0) _push(tokens[i], dest, amounts[i]);
        }
    }

    function setClaimWindow(uint64 newWindow) external onlyOwner {
        if (newWindow < MIN_CLAIM_WINDOW || newWindow > MAX_CLAIM_WINDOW) revert InvalidClaimWindow();
        uint64 previous = claimWindow;
        claimWindow = newWindow;
        emit ClaimWindowUpdated(previous, newWindow);
    }

    function setSanctionsOracle(address newOracle) external onlyOwner {
        address previous = sanctionsOracle;
        sanctionsOracle = newOracle;
        emit SanctionsOracleUpdated(previous, newOracle);
    }

    function setAllowedToken(address token, bool allowed) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        allowedToken[token] = allowed;
        emit AllowedTokenSet(token, allowed);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setTreasuryList(address[] calldata newList) external onlyOwner {
        _setTreasuryList(newList);
    }

    function addTreasury(address treasury) external onlyOwner {
        if (treasury == address(0)) revert InvalidTreasury();
        if (isTreasury[treasury]) revert DuplicateTreasury(treasury);
        isTreasury[treasury] = true;
        treasuries.push(treasury);
        emit TreasuryAdded(treasury);
    }

    function removeTreasury(address treasury) external onlyOwner {
        if (!isTreasury[treasury]) revert TreasuryNotFound(treasury);
        uint256 len = treasuries.length;
        if (len == 1) revert CannotRemoveLastTreasury();

        for (uint256 i = 0; i < len; ++i) {
            if (treasuries[i] == treasury) {
                treasuries[i] = treasuries[len - 1];
                treasuries.pop();
                break;
            }
        }
        isTreasury[treasury] = false;
        emit TreasuryRemoved(treasury);
    }

    function getPool(bytes32 id) external view returns (Pool memory) {
        return pools[id];
    }

    function getLeg(bytes32 id, address token) external view returns (Leg memory) {
        return legs[id][token];
    }

    function getPoolTokens(bytes32 id) external view returns (address[] memory) {
        return poolTokens[id];
    }

    function fundOf(bytes32 id, address token) external view returns (uint256) {
        return _fund(legs[id][token], pools[id].poolBps);
    }

    function isClaimed(bytes32 id, uint256 index) external view returns (bool) {
        return _isClaimed(id, index);
    }

    function getTreasuries() external view returns (address[] memory) {
        return treasuries;
    }

    function treasuryCount() external view returns (uint256) {
        return treasuries.length;
    }

    function _claim(bytes32 id, uint256 index, address account, address token, uint256 amount, bytes32[] calldata proof)
        internal
    {
        Pool storage p = pools[id];
        if (p.regCloseAt == 0) revert PoolUnknown(id);
        if (p.canceledAt != 0) revert PoolCanceled(id);
        if (p.settledAt == 0) revert NotSettled(id);
        if (!isPoolToken[id][token]) revert TokenNotInPool(id, token);
        if (_isClaimed(id, index)) revert AlreadyClaimed(id, index);

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(index, account, token, amount))));
        if (!MerkleProof.verify(proof, p.root, leaf)) revert InvalidProof();

        Leg storage leg = legs[id][token];
        uint256 claimedTotal = leg.claimed + amount;
        if (claimedTotal > leg.prizeTotal) revert ClaimExceedsPool();

        _setClaimed(id, index);
        leg.claimed = claimedTotal;

        emit Claimed(id, index, account, token, amount);

        _push(token, account, amount);
    }

    function _registerTokens(
        bytes32 id,
        address[] calldata tokens,
        uint256[] calldata ticketPrices,
        uint256[] calldata guaranteed
    ) internal returns (uint256 nativeGuarantee) {
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == address(0)) revert InvalidToken();
            if (!allowedToken[token]) revert TokenNotAllowed(token);
            if (isPoolToken[id][token]) revert DuplicateToken(token);
            if (ticketPrices[i] == 0) revert InvalidTicketPrice();

            isPoolToken[id][token] = true;
            poolTokens[id].push(token);
            Leg storage leg = legs[id][token];
            leg.ticketPrice = ticketPrices[i];
            leg.guaranteed = guaranteed[i];
            if (token == NATIVE) nativeGuarantee = guaranteed[i];
        }
    }

    function _pullGuarantees(address[] calldata tokens, uint256[] calldata guaranteed) internal {
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (guaranteed[i] > 0) _pull(tokens[i], guaranteed[i]);
        }
    }

    function _open(bytes32 id) internal view returns (Pool storage p) {
        p = pools[id];
        if (p.regCloseAt == 0) revert PoolUnknown(id);
        if (p.canceledAt != 0) revert PoolCanceled(id);
        if (p.settledAt != 0) revert AlreadySettled(id);
    }

    function _canceled(bytes32 id) internal view returns (Pool storage p) {
        p = pools[id];
        if (p.regCloseAt == 0) revert PoolUnknown(id);
        if (p.canceledAt == 0) revert PoolNotCanceled(id);
    }

    function _fund(Leg storage leg, uint16 poolBps) internal view returns (uint256) {
        uint256 share = (leg.revenue * poolBps) / MAX_POOL_BPS;
        return (share > leg.guaranteed ? share : leg.guaranteed) + leg.sponsored;
    }

    function _requireValue(address token, uint256 amount) internal view {
        uint256 expected = token == NATIVE ? amount : 0;
        if (msg.value != expected) revert InvalidValue(expected, msg.value);
    }

    function _pull(address token, uint256 amount) internal {
        if (token == NATIVE) return;
        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - before;
        if (received < amount) revert TransferShortfall(token, amount, received);
    }

    function _push(address token, address to, uint256 amount) internal {
        if (token == NATIVE) {
            (bool ok,) = payable(to).call{value: amount}("");
            if (!ok) revert NativeTransferFailed(to, amount);
            return;
        }
        IERC20(token).safeTransfer(to, amount);
    }

    function _tryPush(address token, address to, uint256 amount) internal returns (bool) {
        if (token == NATIVE) {
            (bool sent,) = payable(to).call{value: amount, gas: REFUND_PUSH_GAS}("");
            return sent;
        }

        (bool ok, bytes memory ret) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        if (!ok) return false;
        if (ret.length == 0) return token.code.length > 0;
        return ret.length == 32 && abi.decode(ret, (bool));
    }

    function _isClaimed(bytes32 id, uint256 index) internal view returns (bool) {
        uint256 mask = uint256(1) << (index & 0xff);
        return claimedBitmap[id][index >> 8] & mask != 0;
    }

    function _setClaimed(bytes32 id, uint256 index) internal {
        uint256 mask = uint256(1) << (index & 0xff);
        claimedBitmap[id][index >> 8] |= mask;
    }

    function _requireNotSanctioned(address wallet) internal view {
        address oracle = sanctionsOracle;
        if (oracle != address(0) && ISanctionsOracle(oracle).isSanctioned(wallet)) {
            revert SanctionedAddress(wallet);
        }
    }

    function _nextTreasury() internal returns (address dest) {
        uint256 len = treasuries.length;
        uint256 idx = treasuryCursor % len;
        dest = treasuries[idx];
        unchecked {
            treasuryCursor = idx + 1;
        }
    }

    function _setTreasuryList(address[] memory newList) internal {
        if (newList.length == 0) revert EmptyTreasuryList();

        uint256 oldLen = treasuries.length;
        for (uint256 i = 0; i < oldLen; ++i) {
            isTreasury[treasuries[i]] = false;
        }
        delete treasuries;

        for (uint256 i = 0; i < newList.length; ++i) {
            address t = newList[i];
            if (t == address(0)) revert InvalidTreasury();
            if (isTreasury[t]) revert DuplicateTreasury(t);
            isTreasury[t] = true;
            treasuries.push(t);
            emit TreasuryAdded(t);
        }
        treasuryCursor = 0;
        emit TreasuryListSet(newList.length);
    }
}
