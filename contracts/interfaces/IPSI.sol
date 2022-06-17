// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol';
import "./IDEXRouter.sol";
import "./IBEP20.sol";

interface IPSI is IBEP20, IERC20PermitUpgradeable {
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived);
    event SetDefaultDexRouter(address indexed newAddress, address indexed oldAddress);
    event SetDexPair(address indexed pair, bool indexed value);
    event SetLiquidityWallet(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);
    
    function reflectionFee() external view returns (uint256);
    function liquidityBuyFee() external view returns (uint256);
    function liquiditySellFee() external view returns (uint256);
    function swapTokensAtAmount() external view returns (uint256);
    function totalReflectionFees() external view returns (uint256);

    function swapEnabled() external view returns (bool);
    function oldPsiContract() external view returns (address);

    function defaultDexRouter() external view returns (IDEXRouter);
    function defaultPair() external view returns (address);
    function dexPairs(address pair) external view returns (bool);
    function liquidityWallet() external view returns (address);

    //== Swap old contract ==
    function setSwapEnabled(bool value) external;
    function swapOld() external;
    function swapOldAmount(uint256 amount) external;
    function callOld(bytes memory data) external returns (bytes memory);

    //== Include or Exclude account from earning fees ==
    function setAccountExcludedFromFees(address account, bool excluded) external;
    function isExcludedFromFeeRetrieval(address account) external view returns (bool);
    function setAccountExcludedFromFeeRetrieval(address account, bool excluded) external;
    function isExcludedFromFeePayment(address account) external view returns (bool);
    function setAccountExcludedFromFeePayment(address account, bool excluded) external;
    function isExcludedFromDexFeePayment(address account) external view returns (bool);
    function setAccountExcludedDexFromFeePayment(address account, bool excluded) external;

    // Liquidity pairs
    function setDefaultRouter(address _router, address factory) external;
    function setDexPair(address pair, bool value) external;
    function setLiquidityWallet(address newLiquidityWallet) external;

    //== Fees ==
    function setFees(uint256 _reflectionFee, uint256 _liquidityBuyFee, uint256 _liquiditySellFee) external;
    function setSwapTokensAtAmount(uint256 _swapTokensAtAmount) external;

    //== Reflection ==
    function reflect(uint256 tAmount) external;
    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) external view returns(uint256);
    function tokenFromReflection(uint256 rAmount) external view returns(uint256);
}