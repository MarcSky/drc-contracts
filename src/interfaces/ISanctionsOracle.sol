// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ISanctionsOracle {
    function isSanctioned(address addr) external view returns (bool);
}
