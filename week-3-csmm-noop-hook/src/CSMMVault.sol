// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/**
 * @title CSMMVault
 * @notice Handles LP share accounting and asset tracking for the CSMM Hook.
 * @dev This acts as a simple share-based vault where assets are Claim Tokens in the PM.
 */
abstract contract CSMMVault is ERC1155 {
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => uint256) private _totalSupply;

    constructor() ERC1155("") {}

    function totalSupply(PoolId id) public view returns (uint256) {
        return _totalSupply[id];
    }

    /**
     * @notice Returns the assets (claim tokens) supporting the LP shares for a pool.
     * @param manager The Pool Manager instance to query balances from.
     */
    function totalAssets(IPoolManager manager, PoolKey calldata key) 
        public 
        view 
        returns (uint256 amount0, uint256 amount1) 
    {
        amount0 = manager.balanceOf(address(this), key.currency0.toId());
        amount1 = manager.balanceOf(address(this), key.currency1.toId());
    }

    /// @dev Internal hook to track total supply of LP shares per PoolId
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {
        super._update(from, to, ids, values);
        for (uint256 i = 0; i < ids.length; i++) {
            PoolId id = PoolId.wrap(bytes32(ids[i]));
            if (from == address(0)) _totalSupply[id] += values[i];
            if (to == address(0)) _totalSupply[id] -= values[i];
        }
    }
}