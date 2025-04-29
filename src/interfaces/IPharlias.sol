// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IPharlias
 * @dev Interface for the Pharlias points system
 */
interface IPharlias {
    // ================ Errors ================
    /// @notice Thrown when caller is not authorized
    error Unauthorized();
    
    /// @notice Thrown when the system is paused
    error SystemPaused();
    
    /// @notice Thrown when an invalid tier is specified
    error InvalidTier();
    
    /// @notice Thrown when an invalid activity is specified
    error InvalidActivity();
    
    /// @notice Thrown when parameters are invalid
    error InvalidParameters();

    // ================ Events ================
    /**
     * @notice Emitted when points are awarded to a user
     * @param user The user address
     * @param activityId The ID of the activity
     * @param points The number of points awarded
     * @param multiplier The multiplier applied to the points
     * @param totalPoints The new total points for the user
     */
    event PointsAwarded(
        address indexed user,
        uint8 indexed activityId,
        uint256 points,
        uint256 multiplier,
        uint256 totalPoints
    );
    
    /**
     * @notice Emitted when a user's tier changes
     * @param user The user address
     * @param oldTier The old tier ID
     * @param newTier The new tier ID
     */
    event TierChanged(
        address indexed user,
        uint8 oldTier,
        uint8 newTier
    );
    
    /**
     * @notice Emitted when points expire
     * @param user The user address
     * @param points The number of points that expired
     */
    event PointsExpired(
        address indexed user,
        uint256 points
    );
    
    /**
     * @notice Emitted when a new activity is added
     * @param activityId The ID of the activity
     * @param name The name of the activity
     * @param points The base points for the activity
     */
    event ActivityAdded(
        uint8 indexed activityId,
        string name,
        uint256 points
    );
    
    /**
     * @notice Emitted when an activity is updated
     * @param activityId The ID of the activity
     * @param name The name of the activity
     * @param points The base points for the activity
     */
    event ActivityUpdated(
        uint8 indexed activityId,
        string name,
        uint256 points
    );
    
    /**
     * @notice Emitted when a new tier is added
     * @param tierId The ID of the tier
     * @param name The name of the tier
     * @param threshold The points threshold for the tier
     * @param multiplier The points multiplier for the tier
     */
    event TierAdded(
        uint8 indexed tierId,
        string name,
        uint256 threshold,
        uint256 multiplier
    );
    
    /**
     * @notice Emitted when a tier is updated
     * @param tierId The ID of the tier
     * @param name The name of the tier
     * @param threshold The points threshold for the tier
     * @param multiplier The points multiplier for the tier
     */
    event TierUpdated(
        uint8 indexed tierId,
        string name,
        uint256 threshold,
        uint256 multiplier
    );
    
    /**
     * @notice Emitted when the system pause state changes
     * @param paused The new pause state
     */
    event PauseStateChanged(bool paused);
    
    /**
     * @notice Emitted when points expiry period is updated
     * @param expiryPeriod The new expiry period in seconds
     */
    event ExpiryPeriodUpdated(uint256 expiryPeriod);

    // ================ User Functions ================
    /**
     * @notice Get the total points for a user
     * @param user The user address
     * @return The total points for the user
     */
    function getPoints(address user) external view returns (uint256);
    
    /**
     * @notice Get the current tier for a user
     * @param user The user address
     * @return The tier ID of the user
     */
    function getUserTier(address user) external view returns (uint8);
    
    /**
     * @notice Award points for an activity
     * @param user The user address
     * @param activityId The ID of the activity
     */
    function awardPoints(address user, uint8 activityId) external;
    
    /**
     * @notice Award custom points amount
     * @param user The user address
     * @param points The number of points to award
     * @param reason A description of why the points were awarded
     */
    function awardCustomPoints(address user, uint256 points, string calldata reason) external;
    
    /**
     * @notice Process expired points for a user
     * @param user The user address
     * @return The number of points that expired
     */
    function processExpiredPoints(address user) external returns (uint256);

    // ================ Admin Functions ================
    /**
     * @notice Add a new activity
     * @param activityId The ID of the activity
     * @param name The name of the activity
     * @param points The base points for the activity
     */
    function addActivity(uint8 activityId, string calldata name, uint256 points) external;
    
    /**
     * @notice Update an existing activity
     * @param activityId The ID of the activity
     * @param name The name of the activity
     * @param points The base points for the activity
     */
    function updateActivity(uint8 activityId, string calldata name, uint256 points) external;
    
    /**
     * @notice Add a new tier
     * @param tierId The ID of the tier
     * @param name The name of the tier
     * @param threshold The points threshold for the tier
     * @param multiplier The points multiplier for the tier
     */
    function addTier(uint8 tierId, string calldata name, uint256 threshold, uint256 multiplier) external;
    
    /**
     * @notice Update an existing tier
     * @param tierId The ID of the tier
     * @param name The name of the tier
     * @param threshold The points threshold for the tier
     * @param multiplier The points multiplier for the tier
     */
    function updateTier(uint8 tierId, string calldata name, uint256 threshold, uint256 multiplier) external;
    
    /**
     * @notice Set the points expiry period
     * @param expiryPeriod The expiry period in seconds
     */
    function setExpiryPeriod(uint256 expiryPeriod) external;
    
    /**
     * @notice Set the system pause state
     * @param paused The new pause state
     */
    function setPaused(bool paused) external;
}

