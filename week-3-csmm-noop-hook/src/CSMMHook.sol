// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CSMMVault} from "./CSMMVault.sol";

contract CSMMHook is BaseHook, CSMMVault {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    uint256 public constant FEE_BIPS = 100; // 1% Fee
    uint256 public constant BIPS_DIVISOR = 10000;

    error NotPoolManager();
    error CSMMNotSupported();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) CSMMVault() {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true, // Enable beforeSwap for NoOp logic
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true, // Required for NoOp
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Swapping logic for CSMM (1:1 price)
     * @dev Uses NoOp to override PM logic and charges a 1% fee
     */
    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // We only support exact input for this simple CSMM
        if (params.amountSpecified >= 0) revert CSMMNotSupported();

        uint256 amountIn = uint256(-params.amountSpecified);
        uint256 fee = (amountIn * FEE_BIPS) / BIPS_DIVISOR;
        uint256 amountOut = amountIn - fee;

        Currency input = params.zeroForOne ? key.currency0 : key.currency1;
        Currency output = params.zeroForOne ? key.currency1 : key.currency0;

        // 1. Hook takes the input tokens by minting claim tokens from PM
        poolManager.mint(address(this), input.toId(), amountIn);

        // 2. Hook pays the output tokens by burning claim tokens at PM
        poolManager.burn(address(this), output.toId(), amountOut);

        // Construct the delta to NoOp the PM:
        // specified: amountIn (positive because we "consumed" the user's negative debt)
        // unspecified: amountOut (negative because we are providing the tokens)
        BeforeSwapDelta returnDelta = toBeforeSwapDelta(int128(int256(amountIn)), -int128(int256(amountOut)));

        return (this.beforeSwap.selector, returnDelta, 0);
    }

    /**
     * @notice LPs add liquidity directly to the hook
     * @dev Mints claim tokens for the hook and ERC1155 shares for the user
     */
    function addLiquidity(PoolKey calldata key, uint256 amount0, uint256 amount1) external {
        poolManager.unlock(abi.encode(msg.sender, key, amount0, amount1, true));
    }

    /**
     * @notice LPs remove liquidity by burning their shares
     */
    function removeLiquidity(PoolKey calldata key, uint256 lpAmount) external {
        poolManager.unlock(abi.encode(msg.sender, key, lpAmount, uint256(0), false));
    }

    /**
     * @dev Internal callback handled within PoolManager.unlock()
     */
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();

        (address sender, PoolKey memory key, uint256 val1, uint256 val2, bool isAdd) =
            abi.decode(data, (address, PoolKey, uint256, uint256, bool));

        PoolId poolId = key.toId();

        if (isAdd) {
            _handleAddLiquidity(sender, key, val1, val2);
        } else {
            _handleRemoveLiquidity(sender, key, val1);
        }

        return "";
    }

    function _handleAddLiquidity(address sender, PoolKey memory key, uint256 amount0, uint256 amount1) internal {
        // Transfer tokens from user to PM and mint claim tokens to Hook
        if (amount0 > 0) {
            key.currency0.settle(poolManager, sender, amount0, false);
            poolManager.mint(address(this), key.currency0.toId(), amount0);
        }
        if (amount1 > 0) {
            key.currency1.settle(poolManager, sender, amount1, false);
            poolManager.mint(address(this), key.currency1.toId(), amount1);
        }

        // Simple 1:1 share minting for this example (can be refined to use sqrt(a*b))
        uint256 shares = amount0 + amount1;
        _mint(sender, uint256(PoolId.unwrap(key.toId())), shares, "");
    }

    function _handleRemoveLiquidity(address sender, PoolKey memory key, uint256 lpAmount) internal {
        uint256 totalShares = totalSupply(key.toId());
        
        // Calculate proportional share of reserves using the vault logic
        (uint256 reserve0, uint256 reserve1) = totalAssets(poolManager, key);

        uint256 out0 = (reserve0 * lpAmount) / totalShares;
        uint256 out1 = (reserve1 * lpAmount) / totalShares;

        _burn(sender, uint256(PoolId.unwrap(key.toId())), lpAmount);

        // Burn claim tokens to release underlying tokens to the user
        if (out0 > 0) {
            poolManager.burn(address(this), key.currency0.toId(), out0);
            key.currency0.take(poolManager, sender, out0, false);
        }
        if (out1 > 0) {
            poolManager.burn(address(this), key.currency1.toId(), out1);
            key.currency1.take(poolManager, sender, out1, false);
        }
    }
}