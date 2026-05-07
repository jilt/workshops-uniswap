// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CurrencyLibrary} from "v4-core/types/Currency.sol";

import {MockChainlinkFunctions} from "./MockChainlinkFunctions.sol";

/**
 * @title PointsHook - The Loyalty Manager
 * 
 * Sits on top of Uniswap V4 and watches every trade.
 * 
 * FLOW:
 * 1. User Swaps: Spends ETH to buy Token (zeroForOne = true)
 * 2. Hook Wakes Up: Calculates points from ETH spent
 * 3. Identity Check: Requires hookData with user address (reverts if missing)
 * 4. Points Issued: Mints pool-specific ERC-1155 points to user
 * 5. Scoreboard Updates: Tells MockChainlink to update global leaderboard
 * 6. Rank Check: Queries new rank from leaderboard
 * 7. Achievement Unlocked: Upgrades ERC-1155 metadata to new tier
 */
contract PointsHook is BaseHook, ERC1155 {
    
    using CurrencyLibrary for Currency;
    
    // Reference to the Global Scoreboard (MockChainlinkFunctions)
    MockChainlinkFunctions public mockChainlink;
    
    // Track user's current tier for metadata
    mapping(address => uint256) public userCurrentTier;
    
    // Track user's total accumulated points across all pools
    mapping(address => uint256) public userTotalPoints;
    
    // Token ID Namespace to avoid collisions
    uint256 constant TIER_OFFSET = 10000;
    uint256 constant TIER_BASIC = TIER_OFFSET + 1;        // 10001
    uint256 constant TIER_RARE = TIER_OFFSET + 2;         // 10002
    uint256 constant TIER_LEGENDARY = TIER_OFFSET + 3;    // 10003
    
    // Tier thresholds
    uint256 constant POINTS_FOR_RARE = 500;
    uint256 constant POINTS_FOR_LEGENDARY = 1500;
    
    // Events
    event SwapProcessed(
        address indexed user,
        uint256 ethSpent,
        uint256 pointsAwarded,
        uint256 poolId
    );
    event PointsAwarded(
        address indexed user,
        uint256 poolId,
        uint256 points
    );
    event ScoreboardUpdated(
        address indexed user,
        uint256 totalPoints,
        uint256 globalRank
    );
    event TierUpgraded(
        address indexed user,
        uint256 oldTier,
        uint256 newTier
    );

    constructor(
        IPoolManager _manager,
        address _mockChainlink
    ) BaseHook(_manager) {
        mockChainlink = MockChainlinkFunctions(_mockChainlink);
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function uri(uint256 id) public view virtual override returns (string memory) {
        // Tier tokens have distinct URIs
        if (id == TIER_BASIC) {
            return "https://api.example.com/tier/basic";
        } else if (id == TIER_RARE) {
            return "https://api.example.com/tier/rare";
        } else if (id == TIER_LEGENDARY) {
            return "https://api.example.com/tier/legendary";
        }
        // Pool-specific points
        return "https://api.example.com/pool/points/{id}";
    }

    /**
     * THE TRIGGER:
     * Only cares when someone spends ETH to buy a Token.
     * Ignores all other trade types.
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // Validate pool is ETH/TOKEN (currency0 must be ETH)
        if (!key.currency0.isAddressZero()) {
            return (this.afterSwap.selector, 0);
        }

        // IDENTITY CHECK (hookData):
        // Perform this FIRST to save gas. If data is missing, revert immediately.
        require(hookData.length >= 32, "Identity check failed: hookData required");
        
        address user = abi.decode(hookData, (address));
        require(user != address(0), "Identity check failed: invalid user address");

        // Only care about zeroForOne swaps (buying TOKEN with ETH)
        if (!swapParams.zeroForOne) {
            return (this.afterSwap.selector, 0);
        }

        // THE REWARD (Cashback):
        // Calculate ETH spent (delta.amount0 is positive for zeroForOne)
        uint256 ethSpent = uint256(int256(delta.amount0()));
        require(ethSpent > 0, "Invalid swap amount");

        // Points = ETH × 2
        // If you spend 0.5 ETH, you get 1 Point
        // If you spend 1 ETH, you get 2 Points
        uint256 pointsAwarded = ethSpent * 2;

        // Get pool ID
        uint256 poolId = uint256(PoolId.unwrap(key.toId()));

        // STEP 1: Mint Pool-Specific Points (ERC-1155)
        _mint(user, poolId, pointsAwarded, '');
        emit PointsAwarded(user, poolId, pointsAwarded);

        // STEP 2: Update Global Scoreboard (MockChainlinkFunctions)
        // Tell the scoreboard: this user earned points + swap volume
        userTotalPoints[user] += pointsAwarded;
        mockChainlink.addUserToLeaderboard(
            user,
            pointsAwarded,  // Points earned this swap
            1,              // Swap count
            ethSpent        // Volume
        );

        // STEP 3: Rank Check
        // Query leaderboard to get updated global rank
        (uint256 globalRank, uint256 totalPoints,) = mockChainlink.getUserRank(user);
        
        if (globalRank > 0) {
            emit ScoreboardUpdated(user, totalPoints, globalRank);

            // STEP 4: Achievement Unlocked
            // If rank changed, upgrade tier
            _upgradeToNewTier(user, globalRank, totalPoints);
        }

        emit SwapProcessed(user, ethSpent, pointsAwarded, poolId);
        return (this.afterSwap.selector, 0);
    }

    /**
     * THE LEVEL-UP (Tiers):
     * After giving points, checks leaderboard.
     * If rank or points high enough, automatically updates ERC-1155 metadata tier:
     * - Basic: Starting level
     * - Rare: Active traders
     * - Legendary: Top 3 players
     */
    function _upgradeToNewTier(
        address user,
        uint256 globalRank,
        uint256 totalPoints
    ) internal {
        uint256 newTier = TIER_BASIC; // Default starting level

        // TIER_LEGENDARY: Top 3 on leaderboard
        if (globalRank <= 3) {
            newTier = TIER_LEGENDARY;
        }
        // TIER_RARE: Top 4-6 on leaderboard (active traders)
        else if (globalRank <= 6) {
            newTier = TIER_RARE;
        }

        // Also upgrade by points thresholds (for off-leaderboard users)
        if (totalPoints >= POINTS_FOR_LEGENDARY) {
            newTier = TIER_LEGENDARY;
        } else if (totalPoints >= POINTS_FOR_RARE) {
            newTier = TIER_RARE;
        }

        uint256 currentTier = userCurrentTier[user];

        // Only upgrade, never downgrade
        if (newTier > currentTier) {
            _mint(user, newTier, 1, '');
            userCurrentTier[user] = newTier;
            emit TierUpgraded(user, currentTier, newTier);
        }
    }

    /**
     * Public function for manual leaderboard queries (testing/debugging)
     */
    function checkAndUpgradeTier(address user) external {
        (uint256 rank, uint256 totalPoints,) = mockChainlink.getUserRank(user);
        if (rank > 0) {
            _upgradeToNewTier(user, rank, totalPoints);
        }
    }

    /**
     * Get user's profile: tier, total points, and global rank
     */
    function getUserProfile(address user) external view returns (
        uint256 currentTier,
        uint256 totalPoints,
        uint256 globalRank
    ) {
        currentTier = userCurrentTier[user];
        totalPoints = userTotalPoints[user];
        (globalRank,,,) = mockChainlink.getUserRank(user);
    }

    /**
     * Get top 10 players on global scoreboard
     */
    function getGlobalLeaderboard() external view returns (
        MockChainlinkFunctions.LeaderboardEntry[] memory
    ) {
        return mockChainlink.getTopUsers(10);
    }

    /**
     * Admin: Add user to leaderboard (for testing)
     */
    function adminAddToLeaderboard(
        address user,
        uint256 points,
        uint256 swapCount,
        uint256 volume
    ) external {
        mockChainlink.addUserToLeaderboard(user, points, swapCount, volume);
    }
}