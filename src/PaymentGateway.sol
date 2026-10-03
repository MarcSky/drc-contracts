// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPaymentGateway} from "./interfaces/IPaymentGateway.sol";
import {ISanctionsOracle} from "./interfaces/ISanctionsOracle.sol";

contract PaymentGateway is IPaymentGateway, Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    mapping(address token => bool) public supported;

    address[] public treasuries;
    mapping(address treasury => bool) public isTreasury;
    uint256 public treasuryCursor;

    address public sanctionsOracle;

    constructor(address initialOwner, address[] memory initialTreasuries, address[] memory initialSupported)
        Ownable(initialOwner)
    {
        _setTreasuryList(initialTreasuries);

        if (initialSupported.length == 0) revert EmptyInitialWhitelist();
        for (uint256 i = 0; i < initialSupported.length; ++i) {
            address token = initialSupported[i];
            if (token == address(0)) revert TokenNotSupported(token);
            supported[token] = true;
            emit CurrencyUpserted(token, true);
        }
    }

    function payERC20(bytes32 requestId, address token, uint256 amount) external nonReentrant {
        if (requestId == bytes32(0)) revert InvalidRequestId();
        if (amount == 0) revert InvalidAmount();
        if (!supported[token]) revert TokenNotSupported(token);
        _requireNotSanctioned(msg.sender);

        address dest = _nextTreasury();
        emit Paid(requestId, msg.sender, token, amount, dest);

        IERC20(token).safeTransferFrom(msg.sender, dest, amount);
    }

    function payNative(bytes32 requestId) external payable nonReentrant {
        if (requestId == bytes32(0)) revert InvalidRequestId();
        if (msg.value == 0) revert InvalidAmount();
        _requireNotSanctioned(msg.sender);

        address dest = _nextTreasury();
        emit Paid(requestId, msg.sender, address(0), msg.value, dest);

        (bool ok,) = payable(dest).call{value: msg.value}("");
        if (!ok) revert NativeForwardFailed();
    }

    function setSupported(address token, bool enabled) external onlyOwner {
        if (token == address(0)) revert TokenNotSupported(token);
        supported[token] = enabled;
        emit CurrencyUpserted(token, enabled);
    }

    function setSanctionsOracle(address newOracle) external onlyOwner {
        address previous = sanctionsOracle;
        sanctionsOracle = newOracle;
        emit SanctionsOracleUpdated(previous, newOracle);
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

    function sweep(address token, address recipient) external onlyOwner nonReentrant {
        if (!isTreasury[recipient]) revert NotATreasury(recipient);

        if (token == address(0)) {
            uint256 bal = address(this).balance;
            if (bal == 0) revert SweepFailed();
            emit Swept(token, recipient, bal);
            (bool ok,) = payable(recipient).call{value: bal}("");
            if (!ok) revert NativeForwardFailed();
        } else {
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (bal == 0) revert SweepFailed();
            emit Swept(token, recipient, bal);
            IERC20(token).safeTransfer(recipient, bal);
        }
    }

    function getTreasuries() external view returns (address[] memory) {
        return treasuries;
    }

    function treasuryCount() external view returns (uint256) {
        return treasuries.length;
    }

    function _requireNotSanctioned(address payer) internal view {
        address oracle = sanctionsOracle;
        if (oracle != address(0) && ISanctionsOracle(oracle).isSanctioned(payer)) {
            revert SanctionedAddress(payer);
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

    receive() external payable {}
}
