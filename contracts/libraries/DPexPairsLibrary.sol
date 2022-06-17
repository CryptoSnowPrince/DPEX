// SPDX-License-Identifier: MIT

pragma solidity ^0.7.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import '@passive-income/dpex-swap-core/contracts/interfaces/IDPexPair.sol';
import '@passive-income/psi-contracts/contracts/interfaces/IFeeAggregator.sol';
import { DPexLibrary } from './DPexLibrary.sol';

library DPexPairsLibrary {
    using SafeMath for uint;

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, bytes32 initPairHash, address tokenA, address tokenB) 
        internal pure returns (address pair) 
    {
        (address token0, address token1) = DPexLibrary.sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                initPairHash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, bytes32 initPairHash, address tokenA, address tokenB) 
    internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = DPexLibrary.sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IDPexPair(pairFor(factory, initPairHash, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(address feeAggregator, address tokenIn, bool feePayed, 
                        uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 lpFee) 
        internal view returns (uint256 amountOut, uint256 fee)
    {
        require(amountIn > 0, 'DPexLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DPexLibrary: INSUFFICIENT_LIQUIDITY');
        if (lpFee == 0) lpFee = 20; // default 0.2% fee
        if (!feePayed) {
            (fee,) = IFeeAggregator(feeAggregator).calculateFee(tokenIn, amountIn);
            amountIn -= fee;
        }
        amountIn = amountIn.mul(10000 - lpFee);
        uint256 numerator = amountIn.mul(reserveOut);
        uint256 denominator = reserveIn.mul(10000).add(amountIn);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(address feeAggregator, address tokenOut, bool feePayed,
                        uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 lpFee) 
        internal view returns (uint256 amountIn, uint256 fee)
    {
        require(amountOut > 0, 'DPexLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DPexLibrary: INSUFFICIENT_LIQUIDITY');
        if (lpFee == 0) lpFee = 20; // default 0.2% fee
        if (!feePayed) {
            (fee,) = IFeeAggregator(feeAggregator).calculateFee(tokenOut, amountOut);
            amountOut += fee;
        }
        uint256 numerator = reserveIn.mul(amountOut).mul(10000);
        uint256 denominator = reserveOut.sub(amountOut).mul(10000 - lpFee);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address feeAggregator,
        address[] memory factories,
        bytes32[] memory initPairHashes,
        uint256 amountIn,
        address[] memory path,
        uint256[] memory lpFees
    ) internal view returns (uint[] memory amounts, uint256 feeAmount, address feeToken) {
        require(path.length >= 2, 'DPexLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        uint256 feeAmountTmp;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = 
                getReserves(factories[i], initPairHashes[i], path[i], path[i + 1]);
            (amounts[i + 1], feeAmountTmp) = getAmountOut(feeAggregator, path[i], 
                feeAmount > 0 || i > 0, amounts[i], reserveIn, reserveOut, lpFees[i]);
            if (feeAmountTmp > 0) {
                amounts[i] -= feeAmountTmp;
                feeToken = path[i];
                feeAmount = feeAmountTmp;
            }
        }

        if (feeAmount == 0) {
            (feeAmountTmp,) = IFeeAggregator(feeAggregator)
                .calculateFee(path[path.length - 1], amounts[amounts.length - 1]);
            if (feeAmountTmp > 0) {
                amounts[amounts.length - 1] -= feeAmountTmp;
                feeToken = path[path.length - 1];
                feeAmount = feeAmountTmp;
            }
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address feeAggregator,
        address[] memory factories,
        bytes32[] memory initPairHashes,
        uint256 amountOut,
        address[] memory path,
        uint256[] memory lpFees
    ) internal view returns (uint[] memory amounts, uint256 feeAmount, address feeToken) {
        require(path.length >= 2, 'DPexLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        uint256 feeAmountTmp;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = 
                getReserves(factories[i - 1], initPairHashes[i - 1], path[i - 1], path[i]);
            (amounts[i - 1], feeAmountTmp) = getAmountIn(feeAggregator, path[i], 
                feeAmount > 0 || i < amounts.length - 1, amounts[i], reserveIn, reserveOut, lpFees[i - 1]);
            if (feeAmountTmp > 0) {
                feeToken = path[i];
                feeAmount = feeAmountTmp;
            }
        }

        if (feeAmount == 0) {
            (feeAmountTmp,) = IFeeAggregator(feeAggregator).calculateFee(path[0], amounts[0]);
            if (feeAmountTmp > 0) {
                feeToken = path[0];
                feeAmount = feeAmountTmp;
            }
        }
    }
}