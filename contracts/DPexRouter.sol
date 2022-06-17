// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import '@passive-income/dpex-swap-core/contracts/interfaces/IDPexFactory.sol';
import '@passive-income/psi-contracts/contracts/interfaces/IBEP20.sol';
import '@passive-income/psi-contracts/contracts/abstracts/Governable.sol';
import '@passive-income/psi-contracts/contracts/interfaces/IFeeAggregator.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';
import "./interfaces/IDPexRouter.sol";
import "./interfaces/IDPexRouterPairs.sol";
import "./interfaces/IDPexRouterPair.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IDPexWETHWrapper.sol";
import { DPexLibrary } from './libraries/DPexLibrary.sol';

contract DPexRouter is IDPexRouter, Initializable, Governable {
    using SafeMath for uint;

    address public override baseFactory;
    address public override routerPairs;
    address public override WETH;
    address public override WETHWrapper;
    address public override feeAggregator;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'DPexRouter: EXPIRED');
        _;
    }
    modifier onlyAggregator() {
        require(feeAggregator == msg.sender, "DPexRouter: ONLY_FEE_AGGREGATOR");
        _;
    }

    function initialize(
        address _baseFactory,
        address _routerPairs,
        address _WETH,
        address _aggregator,
        address _gov_contract
    ) public initializer {
        super.initialize(_gov_contract);
        baseFactory = _baseFactory;
        routerPairs = _routerPairs;
        WETH = _WETH;
        feeAggregator = _aggregator;
    }

    receive() external payable {
        // only accept ETH via fallback from the WETH contract
        assert(msg.sender == WETH);
    }
    function receiveWETHFunds() external override payable returns(bool success) {
        assert(msg.sender == WETHWrapper);
        return true;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IDPexFactory(baseFactory).getPair(tokenA, tokenB) == address(0)) {
            IDPexFactory(baseFactory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = IDPexRouterPairs(routerPairs).getReserves(baseFactory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = DPexLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'DPexRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = DPexLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'DPexRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) 
    returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = IDPexRouterPairs(routerPairs).pairFor(baseFactory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IDPexRouterPair(pair).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) 
    returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = IDPexRouterPairs(routerPairs).pairFor(baseFactory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IDPexWETHWrapper(WETHWrapper).deposit{value: amountETH}();
        assert(IDPexWETHWrapper(WETHWrapper).transfer(pair, amountETH));
        liquidity = IDPexRouterPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = IDPexRouterPairs(routerPairs).pairFor(baseFactory, tokenA, tokenB);
        IDPexRouterPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IDPexRouterPair(pair).burn(to);
        (address token0,) = DPexLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'DPexRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'DPexRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        assert(IWETH(WETH).transfer(WETHWrapper, amountETH));
        IDPexWETHWrapper(WETHWrapper).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        _permit(tokenA, tokenB, liquidity, deadline, approveMax, v, r ,s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function _permit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) internal {
        IDPexRouterPair(IDPexRouterPairs(routerPairs).pairFor(baseFactory, tokenA, tokenB)).permit(
            msg.sender, 
            address(this), 
            approveMax ? uint(-1) : liquidity,
            deadline,
            v, r, s
        );
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountETH) {
        IDPexRouterPair(IDPexRouterPairs(routerPairs).pairFor(baseFactory, token, WETH)).permit(
            msg.sender,
            address(this),
            approveMax ? uint(-1) : liquidity,
            deadline,
            v, r, s
        );
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IBEP20(token).balanceOf(address(this)));
        assert(IWETH(WETH).transfer(WETHWrapper, amountETH));
        IDPexWETHWrapper(WETHWrapper).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint256 amountETH) {
        address pair = IDPexRouterPairs(routerPairs).pairFor(baseFactory, token, WETH);
        uint256 value = approveMax ? uint(-1) : liquidity;
        IDPexRouterPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    function _swap(
        address[] memory factories, 
        uint[] memory amounts, 
        address[] memory path, 
        address _to, 
        uint256 feeAmount, 
        address feeToken
    ) internal {
        // send initial amount
        transferTokensOrWETH(
            path[0],
            msg.sender,
            IDPexRouterPairs(routerPairs).pairFor(factories[0], path[0],
            path[1]),
            amounts[0]
        );
        if (path[0] == feeToken) transferFeeWhenNeeded(msg.sender, feeToken, feeAmount);

        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = DPexLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            address to = i < path.length - 2 
                ? IDPexRouterPairs(routerPairs).pairFor(factories[i + 1], output, path[i + 2])
                : _to;
            if (to == WETHWrapper && output == path[path.length - 1] && output == feeToken)
                amountOut += feeAmount;

            _trySwap(
                IDPexRouterPair(IDPexRouterPairs(routerPairs).pairFor(factories[i], input, output)),
                input == token0 ? uint256(0) : amountOut,
                input == token0 ? amountOut : uint256(0),
                to
            );

            if (to == WETHWrapper && output == path[path.length - 1] && output == feeToken)
                transferFeeWhenNeeded(WETHWrapper, feeToken, feeAmount);
        }
    }
    function swapExactTokensForTokens(
        address[] calldata factories,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        uint256 feeAmount;
        address feeToken;
        (amounts, feeAmount, feeToken) = IDPexRouterPairs(routerPairs).getAmountsOut(factories, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'DPexRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        _swap(factories, amounts, path, to, feeAmount, feeToken);
    }
    function swapTokensForExactTokens(
        address[] calldata factories,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        uint256 feeAmount;
        address feeToken;
        (amounts, feeAmount, feeToken) = IDPexRouterPairs(routerPairs).getAmountsIn(factories, amountOut, path);

        uint256 totalAmount0 = amounts[0];
        if (path[0] == feeToken) totalAmount0 += feeAmount;
        require(totalAmount0 <= amountInMax, 'DPexRouter: EXCESSIVE_INPUT_AMOUNT');

        _swap(factories, amounts, path, to, feeAmount, feeToken);
    }
    function swapExactETHForTokens(
        address[] calldata factories,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, 'DPexRouter: INVALID_PATH');

        uint256 feeAmount;
        address feeToken;
        (amounts, feeAmount, feeToken) = IDPexRouterPairs(routerPairs).getAmountsOut(factories, msg.value, path);

        require(amounts[amounts.length - 1] >= amountOutMin, 'DPexRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        uint256 totalAmount0 = amounts[0];
        if (path[0] == feeToken) totalAmount0 += feeAmount;
        IDPexWETHWrapper(WETHWrapper).deposit{value: totalAmount0}();

        _swap(factories, amounts, path, to, feeAmount, feeToken);
    }
    function swapTokensForExactETH(
        address[] calldata factories,
        uint256 amountOut,
        uint256 amountInMax, 
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, 'DPexRouter: INVALID_PATH');
        uint256 feeAmount;
        address feeToken;
        (amounts, feeAmount, feeToken) = IDPexRouterPairs(routerPairs).getAmountsIn(factories, amountOut, path);

        uint256 totalAmount0 = amounts[0];
        if (path[0] == feeToken) totalAmount0 += feeAmount;
        require(totalAmount0 <= amountInMax, 'DPexRouter: EXCESSIVE_INPUT_AMOUNT');

        amounts = _swapTokensForETH(factories, amounts, path, to, feeAmount, feeToken);
    }
    function swapExactTokensForETH(
        address[] calldata factories,
        uint256 amountIn,
        uint256 amountOutMin, 
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, 'DPexRouter: INVALID_PATH');
        uint256 feeAmount;
        address feeToken;
        (amounts, feeAmount, feeToken) = IDPexRouterPairs(routerPairs).getAmountsOut(factories, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'DPexRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        amounts = _swapTokensForETH(factories, amounts, path, to, feeAmount, feeToken);
    }
    function _swapTokensForETH(
        address[] calldata factories,
        uint[] memory amounts,
        address[] calldata path, 
        address to,
        uint256 feeAmount,
        address feeToken
    ) internal returns (uint[] memory) {
        _swap(factories, amounts, path, WETHWrapper, feeAmount, feeToken);

        IDPexWETHWrapper(WETHWrapper).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
        return amounts;
    }
    function swapETHForExactTokens(
        address[] calldata factories,
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, 'DPexRouter: INVALID_PATH');

        uint256 feeAmount;
        address feeToken;
        (amounts, feeAmount, feeToken) = IDPexRouterPairs(routerPairs).getAmountsIn(factories, amountOut, path);

        uint256 totalAmount0 = amounts[0];
        if (path[0] == feeToken) totalAmount0 += feeAmount;
        require(totalAmount0 <= msg.value, 'DPexRouter: EXCESSIVE_INPUT_AMOUNT');
        IDPexWETHWrapper(WETHWrapper).deposit{value: totalAmount0}();

        _swap(factories, amounts, path, to, feeAmount, feeToken);

        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - totalAmount0);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory factories, address[] memory path, address _to) 
        internal virtual
    {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = DPexLibrary.sortTokens(input, output);
            IDPexRouterPair pair = IDPexRouterPair(IDPexRouterPairs(routerPairs).pairFor(factories[i], input, output));

            // fee is only payed on the first or last token
            address to = i < path.length - 2 
                ? IDPexRouterPairs(routerPairs).pairFor(factories[i + 1], output, path[i + 2])
                : _to;
            _trySwap(
                pair,
                input == token0 ? uint(0) : _getAmountOut(factories[i], pair, input, token0), 
                input == token0 ? _getAmountOut(factories[i], pair, input, token0) : uint(0),
                to
            );
        }
    }
    function _getAmountOut(address factory, IDPexRouterPair pair, address input, address token0) 
        internal virtual returns (uint256 amountOutput) 
    {
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        uint256 amountInput = IBEP20(input).balanceOf(address(pair)).sub(input == token0 ? reserve0 : reserve1);
        (amountOutput,) = IDPexRouterPairs(routerPairs).getAmountOut(
            factory,
            input,
            true, 
            amountInput,
            input == token0 ? reserve0 : reserve1,
            input == token0 ? reserve1 : reserve0
        );
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        address[] calldata factories,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        (amountIn,) = subtractFee(msg.sender, path[0], amountIn);

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, IDPexRouterPairs(routerPairs).pairFor(factories[0], path[0], path[1]), amountIn
        );

        uint256 balanceBefore = IBEP20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(factories, path, to);
        require(
            IBEP20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'DPexRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        address[] calldata factories,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) {
        require(path[0] == WETH, 'DPexRouter: INVALID_PATH');
        uint256 amountIn = msg.value;
        IDPexWETHWrapper(WETHWrapper).deposit{value: amountIn}();
        
        (amountIn,) = subtractFee(msg.sender, WETH, amountIn);

        assert(IDPexWETHWrapper(WETHWrapper).transfer(IDPexRouterPairs(routerPairs)
            .pairFor(factories[0], path[0], path[1]), amountIn));

        uint256 balanceBefore = IBEP20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(factories, path, to);
        require(
            IBEP20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'DPexRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        address[] calldata factories,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WETH, 'DPexRouter: INVALID_PATH');

        (amountIn,) = subtractFee(msg.sender, path[0], amountIn);
        
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, IDPexRouterPairs(routerPairs).pairFor(factories[0], path[0], path[1]), amountIn
        );

        _swapSupportingFeeOnTransferTokens(factories, path, WETHWrapper);
        uint256 amountOut = IBEP20(WETH).balanceOf(WETHWrapper);
        require(amountOut >= amountOutMin, 'DPexRouter: INSUFFICIENT_OUTPUT_AMOUNT');

        IDPexWETHWrapper(WETHWrapper).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    function _trySwap(IDPexRouterPair pair, uint256 amount0Out, uint256 amount1Out, address to) internal {
        try pair.swap(amount0Out, amount1Out, to, new bytes(0)) {
        } catch (bytes memory /*lowLevelData*/) {
            pair.swap(amount0Out, amount1Out, to);
        }
    }

    
    /** Router internal modifiers */
    function setBaseFactory(address _baseFactory) external override onlyGovernor {
        require(_baseFactory != address(0), "DPexRouter: FACTORY_NO_ADDRESS");
        baseFactory = _baseFactory;
    }
    function setWETHWrapper(address wethWrapper) external override onlyGovernor {
        require(wethWrapper != address(0), "DPexRouter: WETHWrapper_NO_ADDRESS");
        WETHWrapper = wethWrapper;
    }


    /** Aggregator function helpers */
    function setFeeAggregator(address aggregator) external override onlyGovernor {
        require(aggregator != address(0), "DPexRouter: FEE_AGGREGATOR_NO_ADDRESS");
        feeAggregator = aggregator;
    }
    function swapAggregatorToken(
        uint256 amountIn,
        address[] calldata path,
        address to
    ) external virtual override onlyAggregator returns (uint256) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, IDPexRouterPairs(routerPairs).pairFor(baseFactory, path[0], path[1]), amountIn
        );
        uint256 balanceBefore = IBEP20(path[path.length - 1]).balanceOf(to);

        address[] memory factories = new address[](path.length - 1);
        for(uint256 idx = 0; idx < path.length - 1; idx++) {
            factories[idx] = baseFactory;
        }

        _swapSupportingFeeOnTransferTokens(factories, path, to);
        return IBEP20(path[path.length - 1]).balanceOf(to).sub(balanceBefore);
    }

    function subtractFee(address from, address token, uint256 amount) 
        internal virtual returns(uint256 amountLeft, uint256 fee) 
    {
        (fee, amountLeft) = IFeeAggregator(feeAggregator).calculateFee(token, amount);
        if (fee > 0) transferFeeWhenNeeded(from, token, fee);
    }
    function transferFeeWhenNeeded(address from, address token, uint256 fee) internal virtual {
        if (fee > 0) {
            uint256 balanceBefore = IBEP20(token).balanceOf(feeAggregator);
            transferTokensOrWETH(token, from, feeAggregator, fee);
            IFeeAggregator(feeAggregator).addTokenFee(
                token, 
                IBEP20(token).balanceOf(feeAggregator).sub(balanceBefore)
            );
        }
    }
    function transferTokensOrWETH(address token, address from, address to, uint256 amount) internal virtual {
        if (token != WETH) {
            TransferHelper.safeTransferFrom(token, from, to, amount);
        } else {
            assert(IDPexWETHWrapper(WETHWrapper).transfer(to, amount));
        }
    }
}