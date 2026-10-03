// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IPaymentGateway {
    event Paid(
        bytes32 indexed requestId, address indexed payer, address indexed token, uint256 amount, address treasury
    );
    event CurrencyUpserted(address indexed token, bool enabled);
    event TreasuryAdded(address indexed treasury);
    event TreasuryRemoved(address indexed treasury);
    event TreasuryListSet(uint256 count);
    event Swept(address indexed token, address indexed recipient, uint256 amount);
    event SanctionsOracleUpdated(address indexed previousOracle, address indexed newOracle);

    error TokenNotSupported(address token);
    error InvalidAmount();
    error InvalidTreasury();
    error InvalidRequestId();
    error NativeForwardFailed();
    error EmptyInitialWhitelist();
    error EmptyTreasuryList();
    error DuplicateTreasury(address treasury);
    error TreasuryNotFound(address treasury);
    error CannotRemoveLastTreasury();
    error NotATreasury(address recipient);
    error SweepFailed();
    error SanctionedAddress(address payer);

    function payERC20(bytes32 requestId, address token, uint256 amount) external;
    function payNative(bytes32 requestId) external payable;

    function setSupported(address token, bool enabled) external;
    function setTreasuryList(address[] calldata newList) external;
    function addTreasury(address treasury) external;
    function removeTreasury(address treasury) external;
    function sweep(address token, address recipient) external;
    function setSanctionsOracle(address newOracle) external;

    function supported(address token) external view returns (bool);
    function isTreasury(address treasury) external view returns (bool);
    function treasuries(uint256 index) external view returns (address);
    function getTreasuries() external view returns (address[] memory);
    function treasuryCount() external view returns (uint256);
    function treasuryCursor() external view returns (uint256);
    function sanctionsOracle() external view returns (address);
}
