// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./IGovernance.sol";

interface IPSIGovernance is IGovernance {
    function gasToken() external view returns (address);
    function enableGasPromotion() external view returns (bool);
    function router() external view returns (address);
}
