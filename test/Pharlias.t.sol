// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/Pharlias.sol";
import "../src/structs/PharliaStructs.sol";

/**
 * @title PharliasTester
 * @dev Tests for the Pharlias points system
 */
contract PharliasTester is Test {
    // Contract instance
    Pharlias pharlias;
    
    // Test accounts
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);
    address unauthorized = address(0x5);
    
    // Constants from the library for easy access
    uint8 ACTIVITY_TRANSFER = PharliaStructs.ACTIVITY_TRANSFER;
    uint8 ACTIVITY_PNS_CREATION = PharliaStructs.ACTIVITY_PNS_CREATION;
    
    // Custom activity IDs for testing
    uint8 constant ACTIVITY_CUSTOM_1 = 3;
    uint8 constant ACTIVITY_CUSTOM_2 = 4;
    
    // Custom tier IDs for testing
    uint8 constant TIER_CUSTOM_1 = 5;
    uint8 constant TIER_CUSTOM_2 = 6;
    
    // ==== Setup ====
    
    function setUp() public {
        // Set up the prank for deploying the contract
        vm.startPrank(owner);
        
        // Deploy Pharlias
        pharlias = new Pharlias();
        
        // Stop the prank after deployment
        vm.stopPrank();
    }
    
    // ==== Helper Functions ====
    
    /**
     * @notice Helper to award transfer points
     * @param user User address
     * @param count Number of times to award points
     */
    function _awardTransferPoints(address user, uint256 count) internal {
        vm.startPrank(owner);
        for (uint256 i = 0; i < count; i++) {
            pharlias.awardPoints(user, ACTIVITY_TRANSFER);
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Helper to award PNS creation points
     * @param user User address
     * @param count Number of times to award points
     */
    function _awardPNSCreationPoints(address user, uint256 count) internal {
        vm.startPrank(owner);
        for (uint256 i = 0; i < count; i++) {
            pharlias.awardPoints(user, ACTIVITY_PNS_CREATION);
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Helper to check tier progression
     * @param user User address
     * @param expectedTier Expected tier ID
     */
    function _assertUserTier(address user, uint8 expectedTier) internal view {
        uint8 actualTier = pharlias.getUserTier(user);
        assertEq(actualTier, expectedTier, "User tier does not match expected tier");
    }
    
    /**
     * @notice Helper to add a custom activity
     * @param activityId Activity ID
     * @param name Activity name
     * @param points Base points for the activity
     */
    function _addCustomActivity(uint8 activityId, string memory name, uint256 points) internal {
        vm.startPrank(owner);
        pharlias.addActivity(activityId, name, points);
        vm.stopPrank();
    }
    
    /**
     * @notice Helper to add a custom tier
     * @param tierId Tier ID
     * @param name Tier name
     * @param threshold Points threshold
     * @param multiplier Points multiplier
     */
    function _addCustomTier(uint8 tierId, string memory name, uint256 threshold, uint256 multiplier) internal {
        vm.startPrank(owner);
        pharlias.addTier(tierId, name, threshold, multiplier);
        vm.stopPrank();
    }
    
    /**
     * @notice Helper to warp time forward
     * @param timeInSeconds Number of seconds to warp forward
     */
    function _warpForward(uint256 timeInSeconds) internal {
        vm.warp(block.timestamp + timeInSeconds);
    }
    
    // ==== Core Functionality Tests ====
    
    /**
     * @notice Test that initial points are zero
     */
    function testInitialPoints() public view {
        uint256 points = pharlias.getPoints(alice);
        assertEq(points, 0, "Initial points should be zero");
        
        // Also check that initial tier is Bronze (1)
        uint8 tier = pharlias.getUserTier(alice);
        assertEq(tier, 1, "Initial tier should be Bronze (1)");
    }
    
    /**
     * @notice Test awarding transfer points
     */
    function testAwardTransferPoints() public {
        // Award 1 transfer (5 points)
        _awardTransferPoints(alice, 1);
        
        // Check points
        uint256 points = pharlias.getPoints(alice);
        assertEq(points, 5, "User should have 5 points after 1 transfer");
        
        // Award 10 more transfers (50 more points)
        _awardTransferPoints(alice, 10);
        
        // Check points
        points = pharlias.getPoints(alice);
        assertEq(points, 55, "User should have 55 points after 11 transfers");
    }
    
    /**
     * @notice Test awarding PNS creation points
     */
    function testAwardPNSCreationPoints() public {
        // Award 1 PNS creation (20 points)
        _awardPNSCreationPoints(alice, 1);
        
        // Check points
        uint256 points = pharlias.getPoints(alice);
        assertEq(points, 20, "User should have 20 points after 1 PNS creation");
        
        // Award 2 more PNS creations (40 more points)
        _awardPNSCreationPoints(alice, 2);
        
        // Check points
        points = pharlias.getPoints(alice);
        assertEq(points, 60, "User should have 60 points after 3 PNS creations");
    }
    
    /**
     * @notice Test awarding custom points
     */
    function testAwardCustomPoints() public {
        vm.startPrank(owner);
        
        // Award 50 custom points
        pharlias.awardCustomPoints(alice, 50, "Welcome bonus");
        
        // Check points
        uint256 points = pharlias.getPoints(alice);
        assertEq(points, 50, "User should have 50 custom points");
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test tier progression based on points
     */
    function testTierProgression() public {
        // Initially tier should be 1 (Bronze)
        _assertUserTier(alice, 1);
        
        // Award enough points to reach tier 2 (Silver, 100 points)
        // Transfer: 20 * 5 = 100 points
        _awardTransferPoints(alice, 20);
        _assertUserTier(alice, 2);
        
        // Award more points to reach tier 3 (Gold, 500 points)
        // Need 400 more points: 20 * 20 = 400 points (PNS creation)
        _awardPNSCreationPoints(alice, 20);
        _assertUserTier(alice, 3);
        
        // Award more points to reach tier 4 (Platinum, 1000 points)
        // Need 500 more points: 25 * 20 = 500 points (PNS creation)
        _awardPNSCreationPoints(alice, 25);
        _assertUserTier(alice, 4);
    }
    
    /**
     * @notice Test points multiplier based on tier
     */
    function testPointsMultiplier() public {
        // First get user to tier 2 (Silver, 1.1x multiplier)
        _awardTransferPoints(alice, 20); // 100 points
        _assertUserTier(alice, 2);
        
        // Award 1 transfer (5 base points)
        uint256 beforePoints = pharlias.getPoints(alice);
        _awardTransferPoints(alice, 1);
        uint256 afterPoints = pharlias.getPoints(alice);
        
        // With 1.1x multiplier, 5 points becomes 5.5 points (rounded to 5)
        // But total should increase by 5 (100 + 5 = 105)
        assertEq(afterPoints - beforePoints, 5, "Points increase with tier 2 multiplier incorrect");
        
        // Get user to tier 3 (Gold, 1.25x multiplier)
        // Already have 105 points, need 395 more: 20 * 20 = 400 (PNS creation)
        _awardPNSCreationPoints(alice, 20);
        _assertUserTier(alice, 3);
        
        // Award 1 transfer (5 base points)
        beforePoints = pharlias.getPoints(alice);
        _awardTransferPoints(alice, 1);
        afterPoints = pharlias.getPoints(alice);
        
        // With 1.25x multiplier, 5 points becomes 6.25 points (rounded to 6)
        assertEq(afterPoints - beforePoints, 6, "Points increase with tier 3 multiplier incorrect");
    }
    
    /**
     * @notice Test point expiry
     */
    function testPointExpiry() public {
        // Award 50 points
        _awardTransferPoints(alice, 10); // 50 points
        
        // Verify initial points
        uint256 initialPoints = pharlias.getPoints(alice);
        assertEq(initialPoints, 50, "Initial points should be 50");
        
        // Warp forward 1 year + 1 day (past the default expiry period)
        _warpForward(366 days);
        
        // Process expired points
        vm.prank(owner);
        uint256 expiredPoints = pharlias.processExpiredPoints(alice);
        
        // Verify expired points and remaining points
        assertEq(expiredPoints, 50, "All 50 points should have expired");
        assertEq(pharlias.getPoints(alice), 0, "No points should remain after expiry");
    }
    
    /**
     * @notice Test getting user stats
     */
    function testGetUserStats() public {
        // Award points from different activities
        _awardTransferPoints(alice, 5); // 25 points
        _awardPNSCreationPoints(alice, 3); // 60 points
        
        // Get user stats
        PharliaStructs.UserStats memory stats = pharlias.getUserStats(alice);
        
        // Verify stats
        assertEq(stats.user, alice, "User address in stats should match");
        assertEq(stats.activityCount, 8, "Activity count should be 8");
        assertEq(stats.totalPoints, 85, "Total points should be 85");
        assertEq(stats.tier, 1, "Tier should be 1");
        assertEq(keccak256(abi.encodePacked(stats.tierName)), keccak256(abi.encodePacked("Bronze")), "Tier name should be Bronze");
    }
    
    // ==== Admin Functionality Tests ====
    
    /**
     * @notice Test adding a new activity
     */
    function testAddActivity() public {
        // Add a new activity
        _addCustomActivity(ACTIVITY_CUSTOM_1, "Custom Activity", 15);
        
        // Award points for the custom activity
        vm.startPrank(owner);
        pharlias.awardPoints(alice, ACTIVITY_CUSTOM_1);
        vm.stopPrank();
        
        // Verify points
        uint256 points = pharlias.getPoints(alice);
        assertEq(points, 15, "User should have 15 points from custom activity");
    }
    
    /**
     * @notice Test updating an activity
     */
    function testUpdateActivity() public {
        // Add a new activity
        _addCustomActivity(ACTIVITY_CUSTOM_1, "Custom Activity", 15);
        
        // Update the activity
        vm.startPrank(owner);
        pharlias.updateActivity(ACTIVITY_CUSTOM_1, "Updated Custom Activity", 25);
        vm.stopPrank();
        
        // Award points for the updated activity
        vm.startPrank(owner);
        pharlias.awardPoints(alice, ACTIVITY_CUSTOM_1);
        vm.stopPrank();
        
        // Verify points
        uint256 points = pharlias.getPoints(alice);
        assertEq(points, 25, "User should have 25 points from updated activity");
    }
    
    /**
     * @notice Test adding a new tier
     */
    function testAddTier() public {
        // Add a new tier
        _addCustomTier(TIER_CUSTOM_1, "Diamond", 2000, 200); // 2x multiplier
        
        // Award enough points to reach the custom tier
        vm.startPrank(owner);
        pharlias.awardCustomPoints(alice, 2000, "Boost to Diamond tier");
        vm.stopPrank();
        
        // Verify tier
        _assertUserTier(alice, TIER_CUSTOM_1);
        
        // Award points with the new multiplier
        uint256 beforePoints = pharlias.getPoints(alice);
        _awardTransferPoints(alice, 1); // 5 base points
        uint256 afterPoints = pharlias.getPoints(alice);
        
        // With 2x multiplier, 5 points becomes 10 points
        assertEq(afterPoints - beforePoints, 10, "Points increase with custom tier multiplier incorrect");
    }
    
    /**
     * @notice Test updating a tier
     */
    function testUpdateTier() public {
        // Add a new tier
        _addCustomTier(TIER_CUSTOM_1, "Diamond", 2000, 200); // 2x multiplier
        
        // Update the tier
        vm.startPrank(owner);
        pharlias.updateTier(TIER_CUSTOM_1, "Super Diamond", 1500, 250); // 2.5x multiplier
        vm.stopPrank();
        
        // Award enough points to reach the updated tier
        vm.startPrank(owner);
        pharlias.awardCustomPoints(alice, 1500, "Boost to Super Diamond tier");
        vm.stopPrank();
        
        // Verify tier
        _assertUserTier(alice, TIER_CUSTOM_1);
        
        // Award points with the new multiplier
        uint256 beforePoints = pharlias.getPoints(alice);
        _awardTransferPoints(alice, 1); // 5 base points
        uint256 afterPoints = pharlias.getPoints(alice);
        
        // With 2.5x multiplier, 5 points becomes 12.5 points (rounded to 12)
        assertEq(afterPoints - beforePoints, 12, "Points increase with updated tier multiplier incorrect");
    }
    
    /**
     * @notice Test pausing the contract
     */
    function testPauseContract() public {
        // Pause the contract
        vm.startPrank(owner);
        pharlias.setPaused(true);
        vm.stopPrank();
        
        // Try to award points (should revert)
        vm.startPrank(owner);
        // OpenZeppelin's Pausable throws EnforcedPause error
        vm.expectRevert(Pausable.EnforcedPause.selector);
        pharlias.awardPoints(alice, ACTIVITY_TRANSFER);
        vm.stopPrank();
        
        // Unpause the contract
        vm.startPrank(owner);
        pharlias.setPaused(false);
        vm.stopPrank();
        
        // Should be able to award points again
        _awardTransferPoints(alice, 1);
        assertEq(pharlias.getPoints(alice), 5, "User should have 5 points after contract unpaused");
    }
    
    /**
     * @notice Test changing the expiry period
     */
    function testChangeExpiryPeriod() public {
        // Set a shorter expiry period (30 days)
        vm.startPrank(owner);
        pharlias.setExpiryPeriod(30 days);
        vm.stopPrank();
        
        // Award points
        _awardTransferPoints(alice, 10); // 50 points
        
        // Warp forward 31 days (past the new expiry period)
        _warpForward(31 days);
        
        // Process expired points
        vm.prank(owner);
        uint256 expiredPoints = pharlias.processExpiredPoints(alice);
        
        // Verify all points expired with the new expiry period
        assertEq(expiredPoints, 50, "All 50 points should have expired with new expiry period");
        assertEq(pharlias.getPoints(alice), 0, "No points should remain after expiry");
    }
    
    /**
     * @notice Test disabling points expiry
     */
    function testDisableExpiry() public {
        // Award points
        _awardTransferPoints(alice, 10); // 50 points
        
        // Disable expiry
        vm.startPrank(owner);
        pharlias.setExpiryEnabled(false);
        vm.stopPrank();
        
        // Warp forward 2 years (well past the default expiry period)
        _warpForward(2 * 365 days);
        
        // Process expired points
        vm.prank(owner);
        uint256 expiredPoints = pharlias.processExpiredPoints(alice);
        
        // Verify no points expired because expiry was disabled
        assertEq(expiredPoints, 0, "No points should expire when expiry is disabled");
        assertEq(pharlias.getPoints(alice), 50, "All points should remain when expiry is disabled");
    }
    
    // ==== Unauthorized Access Tests ====
    
    /**
     * @notice Test unauthorized access to admin functions
     */
    function testUnauthorizedAdmin() public {
        // Try to add activity as unauthorized user
        vm.startPrank(unauthorized);
        vm.expectRevert();
        pharlias.addActivity(ACTIVITY_CUSTOM_1, "Unauthorized Activity", 15);
        
        // Try to update tier as unauthorized user
        vm.expectRevert();
        pharlias.updateTier(1, "Unauthorized Tier", 100, 110);
        
        // Try to set expiry period as unauthorized user
        vm.expectRevert();
        pharlias.setExpiryPeriod(30 days);
        
        // Try to pause contract as unauthorized user
        vm.expectRevert();
        pharlias.setPaused(true);
        vm.stopPrank();
    }
    
    /**
     * @notice Test unauthorized custom point awards
     */
    function testUnauthorizedCustomPoints() public {
        // Try to award custom points as unauthorized user
        vm.startPrank(unauthorized);
        vm.expectRevert();
        pharlias.awardCustomPoints(alice, 100, "Unauthorized bonus");
        vm.stopPrank();
    }
    
    // ==== Edge Case Tests ====
    
    /**
     * @notice Test invalid activity ID
     */
    function testInvalidActivity() public {
        // Try to award points for an invalid activity ID
        vm.startPrank(owner);
        vm.expectRevert(IPharlias.InvalidActivity.selector);
        pharlias.awardPoints(alice, 99); // Activity ID 99 doesn't exist
        vm.stopPrank();
    }
    
    /**
     * @notice Test zero point awards
     */
    function testZeroPointActivity() public {
        // Add a zero-point activity
        _addCustomActivity(ACTIVITY_CUSTOM_2, "Zero Point Activity", 0);
        
        // Award points for the zero-point activity
        vm.startPrank(owner);
        pharlias.awardPoints(alice, ACTIVITY_CUSTOM_2);
        vm.stopPrank();
        
        // Verify user has zero points
        uint256 points = pharlias.getPoints(alice);
        assertEq(points, 0, "User should have 0 points from zero-point activity");
    }
    
    /**
     * @notice Test invalid tier updates
     */
    function testInvalidTierUpdates() public {
        // Try to add a tier with invalid multiplier (above max)
        vm.startPrank(owner);
        vm.expectRevert(IPharlias.InvalidParameters.selector);
        pharlias.addTier(TIER_CUSTOM_1, "Invalid Tier", 1000, 1000); // Max multiplier is 500
        vm.stopPrank();
        
        // Try to add a tier with empty name
        vm.startPrank(owner);
        vm.expectRevert(IPharlias.InvalidParameters.selector);
        pharlias.addTier(TIER_CUSTOM_1, "", 1000, 200);
        vm.stopPrank();
    }
    
    /**
     * @notice Test points expiry edge cases
     */
    function testPointsExpiryEdgeCases() public {
        // Set a fixed start time for better predictability
        uint256 startTime = 1000;
        vm.warp(startTime);
        
        // Award first batch of points at t=1000
        vm.prank(owner);
        pharlias.awardCustomPoints(alice, 50, "First batch");
        assertEq(pharlias.getPoints(alice), 50, "Initial points should be 50");

        // Warp forward 6 months
        vm.warp(startTime + 182 days);

        // Award second batch at t=1000 + 182 days
        vm.prank(owner);
        pharlias.awardCustomPoints(alice, 50, "Second batch");
        assertEq(pharlias.getPoints(alice), 100, "Total points should be 100");

        // Warp to just after first batch expiry (1 year + 1 second from start)
        vm.warp(startTime + 365 days + 1);

        // Process first expiry
        vm.prank(owner);
        uint256 expired = pharlias.processExpiredPoints(alice);
        assertEq(expired, 50, "First batch should expire");
        assertEq(pharlias.getPoints(alice), 50, "Second batch should remain");

        // Warp to just after second batch expiry (1 year from second batch award)
        vm.warp(startTime + 182 days + 365 days + 1);

        // Process second expiry
        vm.prank(owner);
        expired = pharlias.processExpiredPoints(alice);
        assertEq(expired, 50, "Second batch should expire");
        assertEq(pharlias.getPoints(alice), 0, "No points should remain");
    }
    
    // ==== Integration Tests ====
    
    /**
     * @notice Test complete user journey
     */
    function testCompleteUserJourney() public {
        // 1. User starts with zero points and Bronze tier
        assertEq(pharlias.getPoints(alice), 0, "Initial points should be zero");
        _assertUserTier(alice, 1); // Ensure starting tier is Bronze
        
        // 2. User performs transfers and PNS creations
        _awardTransferPoints(alice, 10); // 50 points
        _awardPNSCreationPoints(alice, 3); // 60 points
        
        // 3. User now has enough points for Silver tier (110 points > 100 threshold)
        assertEq(pharlias.getPoints(alice), 110, "User should have 110 points");
        _assertUserTier(alice, 2); // Silver
        
        // 4. More activity with multiplier effect
        _awardTransferPoints(alice, 1); // 5 * 1.1 = 5.5 (rounded to 5) with Silver tier
        assertEq(pharlias.getPoints(alice), 115, "Points with Silver tier multiplier");
        
        // 5. Time passes, some points expire
        _warpForward(366 days);
        vm.prank(owner);
        uint256 expiredPoints = pharlias.processExpiredPoints(alice);
        assertEq(expiredPoints, 115, "All 115 points should expire");
        
        // 6. User tier drops back to Bronze
        _assertUserTier(alice, 1); // Bronze
        
        // 7. User starts earning points again
        _awardPNSCreationPoints(alice, 25); // 500 points, enough for Gold tier
        _assertUserTier(alice, 3); // Gold
        
        // 8. User benefits from higher multiplier
        uint256 beforePoints = pharlias.getPoints(alice);
        _awardTransferPoints(alice, 1); // 5 * 1.25 = 6.25 (rounded to 6) with Gold tier
        uint256 afterPoints = pharlias.getPoints(alice);
        assertEq(afterPoints - beforePoints, 6, "Points increase with Gold tier multiplier");
    }
    
    /**
     * @notice Test multiple activities and tier transitions
     */
    function testMultipleActivitiesAndTiers() public {
        // Add more activities
        _addCustomActivity(ACTIVITY_CUSTOM_1, "Referral", 30);
        _addCustomActivity(ACTIVITY_CUSTOM_2, "Review", 15);
        
        // User performs multiple activities
        _awardTransferPoints(alice, 5); // 25 points
        _awardPNSCreationPoints(alice, 1); // 20 points
        
        vm.startPrank(owner);
        pharlias.awardPoints(alice, ACTIVITY_CUSTOM_1); // 30 points
        pharlias.awardPoints(alice, ACTIVITY_CUSTOM_2); // 15 points
        vm.stopPrank();
        
        // Check total points and tier
        assertEq(pharlias.getPoints(alice), 90, "User should have 90 points from multiple activities");
        _assertUserTier(alice, 1); // Still Bronze
        
        // One more activity to reach Silver
        _awardTransferPoints(alice, 2); // 10 points
        assertEq(pharlias.getPoints(alice), 100, "User should have 100 points");
        _assertUserTier(alice, 2); // Silver
        
        // Get user stats to check activity counts
        PharliaStructs.UserStats memory stats = pharlias.getUserStats(alice);
        assertEq(stats.activityCount, 10, "User should have 10 activities recorded");
        assertEq(stats.tier, 2, "User should be in tier 2 (Silver)");
        assertEq(keccak256(abi.encodePacked(stats.tierName)), keccak256(abi.encodePacked("Silver")), "Tier name should be Silver");
    }
    
    /**
     * @notice Test tier progression with multiple users
     */
    function testMultipleUserTierProgression() public {
        // Alice and Bob both do activities
        _awardTransferPoints(alice, 10); // 50 points
        _awardTransferPoints(bob, 25); // 125 points
        
        // Check tiers
        _assertUserTier(alice, 1); // Bronze
        _assertUserTier(bob, 2); // Silver
        
        // More activities
        _awardPNSCreationPoints(alice, 23); // 460 points
        _awardPNSCreationPoints(bob, 18); // 360 points
        
        // Alice should advance to Gold tier (510 total points)
        _assertUserTier(alice, 3); // Gold
        
        // Bob also reaches Gold tier (485 points, which is apparently enough)
        _assertUserTier(bob, 3); // Gold tier
        
        // One more PNS creation for Bob
        _awardPNSCreationPoints(bob, 1); // 20 more points (505 total)
        _assertUserTier(bob, 3); // Still Gold
    }
}
