// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface IGovernance {
    function isMastermind(address _address) external view returns (bool);
    function isGovernor(address _address) external view returns (bool);
    function isPartner(address _address) external view returns (bool);
    function isUser(address _address) external view returns (bool);
}
