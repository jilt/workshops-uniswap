// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ILoaderboard {
    struct LeaderboardEntry {
        address user;
        uint256 points;
        uint256 swapCount;
        uint256 totalVolume;
    }

    function getUserRank(address user) external view returns (
        uint256 rank,
        uint256 points,
        uint256 swapCount
    );

    function addUserToLeaderboard(
        address user,
        uint256 points,
        uint256 swapCount,
        uint256 totalVolume
    ) external;

    function getTopUsers(uint256 limit) external view returns (LeaderboardEntry[] memory);
}