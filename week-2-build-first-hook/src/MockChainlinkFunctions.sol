// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MockChainlinkFunctions - The Global Scoreboard
 * 
 * In a real-world app, calculating a "Global Rank" is too expensive 
 * to do directly on blockchain. You'd use Chainlink to talk to an 
 * external database (Space and Time).
 * 
 * Since testing locally, this "Mock" acts as that external database.
 * 
 * RESPONSIBILITY:
 * - Keeps top 10 users across the whole system
 * - Calculates rankings by total points + trade volume
 * - Connects with the Hook to provide rank data
 */

contract MockChainlinkFunctions {
    
    struct LeaderboardEntry {
        address user;
        uint256 points;      // Total points earned
        uint256 swapCount;   // How many swaps made
        uint256 totalVolume; // Total ETH volume traded
    }
    
    // THE LEADERBOARD: Top 10 users
    LeaderboardEntry[] public leaderboard;
    
    // Events
    event UserAdded(address indexed user, uint256 points);
    event UserUpdated(address indexed user, uint256 newPoints, uint256 newRank);
    
    constructor() {
        _initializeDefaultLeaderboard();
    }
    
    /**
     * Initialize with 10 test users for demo purposes
     */
    function _initializeDefaultLeaderboard() internal {
        leaderboard.push(LeaderboardEntry(address(0x1111111111111111111111111111111111111111), 5000, 50, 100 ether));
        leaderboard.push(LeaderboardEntry(address(0x2222222222222222222222222222222222222222), 4500, 45, 95 ether));
        leaderboard.push(LeaderboardEntry(address(0x3333333333333333333333333333333333333333), 4000, 40, 80 ether));
        leaderboard.push(LeaderboardEntry(address(0x4444444444444444444444444444444444444444), 3500, 35, 70 ether));
        leaderboard.push(LeaderboardEntry(address(0x5555555555555555555555555555555555555555), 3000, 30, 60 ether));
        leaderboard.push(LeaderboardEntry(address(0x6666666666666666666666666666666666666666), 2500, 25, 50 ether));
        leaderboard.push(LeaderboardEntry(address(0x7777777777777777777777777777777777777777), 2000, 20, 40 ether));
        leaderboard.push(LeaderboardEntry(address(0x8888888888888888888888888888888888888888), 1500, 15, 30 ether));
        leaderboard.push(LeaderboardEntry(address(0x9999999999999999999999999999999999999999), 1000, 10, 20 ether));
        leaderboard.push(LeaderboardEntry(address(0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa), 500, 5, 10 ether));
    }
    
    /**
     * RANKINGS: Calculate who is #1, #2, etc.
     * 
     * Called by the Hook after user earns points:
     * "Hey, this user just earned points. What's their rank now?"
     */
    function getUserRank(address user) external view returns (
        uint256 rank,
        uint256 points,
        uint256 swapCount
    ) {
        // Search leaderboard for this user
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i].user == user) {
                // Found! Return rank (1-indexed), points, and swap count
                return (i + 1, leaderboard[i].points, leaderboard[i].swapCount);
            }
        }
        // Not found on leaderboard
        return (0, 0, 0);
    }
    
    /**
     * THE CONNECTION: When Hook finishes a swap, it sends data here.
     * 
     * Leaderboard tells Hook:
     * "Hey, this user is now ranked #2 globally"
     * → Hook can decide if user deserves level upgrade
     */
    function addUserToLeaderboard(
        address user,
        uint256 points,
        uint256 swapCount,
        uint256 totalVolume
    ) external {
        // Check if user already on leaderboard
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i].user == user) {
                // Update existing user
                leaderboard[i].points += points;
                leaderboard[i].swapCount += swapCount;
                leaderboard[i].totalVolume += totalVolume;
                
                // Re-sort leaderboard by points (simple bubble sort for small size)
                _resortLeaderboard();
                emit UserUpdated(user, leaderboard[i].points, i + 1);
                return;
            }
        }
        
        // User not on leaderboard - try to add
        if (leaderboard.length < 10) {
            // Space available
            leaderboard.push(LeaderboardEntry(user, points, swapCount, totalVolume));
            _resortLeaderboard();
            emit UserAdded(user, points);
        } else {
            // Leaderboard full - replace lowest scorer if new user beats them
            uint256 minIdx = 0;
            for (uint256 i = 1; i < leaderboard.length; i++) {
                if (leaderboard[i].points < leaderboard[minIdx].points) {
                    minIdx = i;
                }
            }
            
            if (points > leaderboard[minIdx].points) {
                leaderboard[minIdx] = LeaderboardEntry(user, points, swapCount, totalVolume);
                _resortLeaderboard();
                emit UserAdded(user, points);
            }
        }
    }
    
    /**
     * Internal: Resort leaderboard by points (descending)
     */
    function _resortLeaderboard() internal {
        uint256 n = leaderboard.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (leaderboard[j].points < leaderboard[j + 1].points) {
                    // Swap
                    (leaderboard[j], leaderboard[j + 1]) = (leaderboard[j + 1], leaderboard[j]);
                }
            }
        }
    }
    
    /**
     * Get top N users from leaderboard
     */
    function getTopUsers(uint256 limit) external view returns (LeaderboardEntry[] memory) {
        uint256 count = limit < leaderboard.length ? limit : leaderboard.length;
        LeaderboardEntry[] memory topUsers = new LeaderboardEntry[](count);
        
        for (uint256 i = 0; i < count; i++) {
            topUsers[i] = leaderboard[i];
        }
        
        return topUsers;
    }
    
    /**
     * Get leaderboard size
     */
    function getLeaderboardLength() external view returns (uint256) {
        return leaderboard.length;
    }
    
    /**
     * Get entry at specific rank
     */
    function getLeaderboardEntry(uint256 index) external view returns (LeaderboardEntry memory) {
        require(index < leaderboard.length, "Index out of bounds");
        return leaderboard[index];
    }
    
    /**
     * Admin: Manually update entry (for testing)
     */
    function adminUpdateEntry(
        uint256 index,
        address user,
        uint256 points,
        uint256 swapCount,
        uint256 totalVolume
    ) external {
        require(index < leaderboard.length, "Index out of bounds");
        leaderboard[index] = LeaderboardEntry(user, points, swapCount, totalVolume);
        _resortLeaderboard();
    }

    /**
     * Mock Chainlink Functions request interface
     */
    function sendRequest(
        bytes memory,
        bytes memory,
        string memory,
        bytes memory,
        bytes[] memory,
        uint64,
        uint32,
        bytes32
    ) external pure returns (bytes32) {
        return keccak256("mock_request_id");
    }
}