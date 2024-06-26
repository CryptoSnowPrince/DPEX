// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.4;

interface IDPexRouterPairs {
    function feeAggregator() external returns (address);

    function pairFor(address factory, address tokenA, address tokenB) external view returns (address pair);
    function getReserves(address factory, address tokenA, address tokenB) 
        external view returns (uint256 reserveA, uint256 reserveB);
    function getAmountOut(address factory, address tokenIn, uint256 amountIn, 
        uint256 reserveIn, uint256 reserveOut) 
        external view returns (uint256 amountOut, uint256 fee);
    function getAmountOut(address factory, address tokenIn, bool feePayed, uint256 amountIn, 
        uint256 reserveIn, uint256 reserveOut)
        external view returns (uint256 amountOut, uint256 fee);
    function getAmountIn(address factory, address tokenOut, uint256 amountOut, 
        uint256 reserveIn, uint256 reserveOut) 
        external view returns (uint256 amountIn, uint256 fee);
    function getAmountIn(address factory, address tokenOut, bool feePayed, uint256 amountOut, 
        uint256 reserveIn, uint256 reserveOut) 
        external view returns (uint256 amountIn, uint256 fee);
    function getAmountsOut(address[] calldata _factories, uint amountIn, address[] calldata path) 
        external view returns (uint[] memory amounts, uint256 feePayed, address feeToken);
    function getAmountsIn(address[] calldata _factories, uint amountOut, address[] calldata path) 
        external view returns (uint[] memory amounts, uint256 feePayed, address feeToken);

    function setFeeAggregator(address aggregator) external;
    function setFactory(address _factory, bytes32 initHash) external returns (bool);
    function removeFactory(address _factory) external returns (bool);
    function hasFactory(address _factory) external view returns (bool);
    function allFactories() external view returns (address[] memory);
    function setLPFee(address _factory, uint256 fee) external;
}