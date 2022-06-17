// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.4;

import '@passive-income/psi-contracts/contracts/abstracts/Governable.sol';
import "./interfaces/IDPexWETHWrapper.sol";
import "./interfaces/IDPexRouter.sol";
import "./interfaces/IWETH.sol";

contract DPexWETHWrapper is IDPexWETHWrapper, Governable {
    address public override router;
    address public override WETH;

    constructor(address _router, address _weth, address _gov_contract) {
        router = _router;
        WETH = _weth;
        gov_contract = _gov_contract;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function deposit() external override payable {
        require(msg.sender == router, "DPexWETHWrapper: ONLY_DPEX_ROUTER_ALLOWED_DEPOSIT");
        IWETH(WETH).deposit{value: msg.value}();
    }
    function withdraw(uint wad) external override {
        require(msg.sender == router, "DPexWETHWrapper: ONLY_DPEX_ROUTER_ALLOWED_WITHDRAW");
        IWETH(WETH).withdraw(wad);
        assert(IDPexRouter(router).receiveWETHFunds{ value: wad }());
    }
    function transfer(address dst, uint wad) external override returns (bool) {
        require(msg.sender == router, "DPexWETHWrapper: ONLY_DPEX_ROUTER_ALLOWED_TRANSFER");
        return IWETH(WETH).transfer(dst, wad);
    }

    function setRouter(address _router) external override onlyGovernor {
        require(_router != address(0), "DPexWETHWrapper: ROUTER_NO_ADDRESS");
        router = _router;
    }
}