// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IOracle} from "../src/interfaces/IOracle.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract MockOracle is IOracle {
    uint160 public price;

    function setPrice(uint160 _price) external {
        price = _price;
    }

    function getOraclePrice(PoolId) external view override returns (uint160) {
        return price;
    }
}