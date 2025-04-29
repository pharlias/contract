// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title PharliaStructs
 * @dev Contains structs and constants for the Pharlias points system
 */
library PharliaStructs {
    // ================ Constants ================
    
    /// @notice Default expiry period for points (365 days)
    uint256 constant DEFAULT_EXPIRY_PERIOD = 365 days;
    
    /// @notice Maximum multiplier value (500 = 5x)
    uint256 constant MAX_MULTIPLIER = 500;
    
    /// @notice Multiplier base (100 = 1x)
    uint256 constant MULTIPLIER_BASE = 100;
    
    /// @notice Activity IDs
    uint8 constant ACTIVITY_TRANSFER = 1;
    uint8 constant ACTIVITY_PNS_CREATION = 2;
    
    // ================ Structs ================
    
    /**
     * @notice Structure for point entries
     * @param amount The number of points
     * @param timestamp The timestamp when the points were awarded
     * @param expiresAt The timestamp when the points expire
     * @param activityId The ID of the activity that generated the points
     */
    struct PointEntry {
        uint256 amount;
        uint256 timestamp;
        uint256 expiresAt;
        uint8 activityId;
    }
    
    /**
     * @notice Structure for user profile
     * @param totalPoints The total points for the user
     * @param tier The current tier of the user
     * @param lastActivityTimestamp The timestamp of the user's last activity
     * @param pointEntries Array of point entries for the user
     */
    struct UserProfile {
        uint256 totalPoints;
        uint8 tier;
        uint256 lastActivityTimestamp;
        PointEntry[] pointEntries;
        mapping(uint8 => uint256) activityCounts; // activity ID => count
    }
    
    /**
     * @notice Structure for activities
     * @param name The name of the activity
     * @param points The base points for the activity
     * @param active Whether the activity is active
     */
    struct Activity {
        string name;
        uint256 points;
        bool active;
    }
    
    /**
     * @notice Structure for tiers
     * @param name The name of the tier
     * @param threshold The points threshold for the tier
     * @param multiplier The points multiplier for the tier (100 = 1x)
     * @param active Whether the tier is active
     */
    struct Tier {
        string name;
        uint256 threshold;
        uint256 multiplier;
        bool active;
    }
    
    /**
     * @notice Structure for user activity statistics
     * @param user The user address
     * @param activityCount The total number of activities
     * @param lastActivityTimestamp The timestamp of the last activity
     * @param totalPoints The total points
     * @param tier The current tier
     */
    struct UserStats {
        address user;
        uint256 activityCount;
        uint256 lastActivityTimestamp;
        uint256 totalPoints;
        uint8 tier;
        string tierName;
    }
}

