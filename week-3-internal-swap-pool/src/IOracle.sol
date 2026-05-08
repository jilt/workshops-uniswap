// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';

interface IOracle {
    function getOraclePrice(PoolId poolId) external view returns (uint160);
}