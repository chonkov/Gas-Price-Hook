// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

contract GasPriceFeesHook is BaseHook {
    using LPFeeLibrary for uint24;
    using FixedPointMathLib for uint256;

    // Keeping track of the moving average gas price
    uint128 public movingAverageGasPrice;
    // How many times has the moving average been updated?
    // Needed as the denominator to update it the next time based on the moving average formula
    uint104 public movingAverageGasPriceCount;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 5000; // 0.5%

    error MustUseDynamicFee();

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        updateMovingAverage();
    }

    // Update our moving average gas price
    function updateMovingAverage() internal {
        uint128 gasPrice = uint128(tx.gasprice);

        // New Average = ((Old Average * # of Txns Tracked) + Current Gas Price) / (# of Txns Tracked + 1)
        movingAverageGasPrice =
            ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) / (movingAverageGasPriceCount + 1);

        movingAverageGasPriceCount++;
    }

    function beforeInitialize(address, PoolKey calldata key, uint160, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        // `.isDynamicFee()` function comes from using
        // the `SwapFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        onlyByPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint128 currentGasPrice = uint128(tx.gasprice);

        uint24 fee = uint24(uint256(BASE_FEE).mulDivDown(currentGasPrice, movingAverageGasPrice));
        poolManager.updateDynamicLPFee(key, fee);

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        updateMovingAverage();
        return (this.afterSwap.selector, 0);
    }

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
