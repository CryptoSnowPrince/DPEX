// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.4;

interface IDPexWETHWrapper {
    function router() external returns (address);
    function WETH() external returns (address);

    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address dst, uint wad) external returns (bool);

    function setRouter(address _router) external;
}