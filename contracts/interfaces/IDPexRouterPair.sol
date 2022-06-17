// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.4;

import '@passive-income/dpex-swap-core/contracts/interfaces/IDPexPair.sol';

interface IDPexRouterPair is IDPexPair {
    function swap(uint amount0Out, uint amount1Out, address to) external;
}
