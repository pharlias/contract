// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/RentRegistrar.sol";
import "../src/ENSRegistry.sol";
import "../src/NFTRegistrar.sol";

contract RentRegistrarTest is Test {
    RentRegistrar rentRegistrar;
    ENSRegistry ens;
    NFTRegistrar nft;
    
    // Test accounts
    address deployer = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    
    // Root node for domain registration
    bytes32 rootNode = keccak256(bytes("pharos"));
    
    // Common test values
    string testDomainName = "test";
    bytes32 testLabel;
    bytes32 testNode;
    string tokenURI = "https://example.com/metadata/test";
    
    function setUp() public {
        vm.startPrank(deployer);
        
        // Deploy contracts
        ens = new ENSRegistry();
        nft = new NFTRegistrar();
        rentRegistrar = new RentRegistrar(ens, nft, rootNode);
        
        // Setup ownership in ENS registry for the root node
        ens.setOwner(rootNode, address(rentRegistrar));
        
        // Transfer ownership of contracts to RentRegistrar
        nft.transferOwnership(address(rentRegistrar));
        ens.transferOwnership(address(rentRegistrar));
        
        vm.stopPrank();
        
        // Precompute values used in multiple tests
        testLabel = keccak256(bytes(testDomainName));
        testNode = keccak256(abi.encodePacked(rootNode, testLabel));
    }
    
    function testDeployment() public view {
        assertEq(address(rentRegistrar.ens()), address(ens));
        assertEq(address(rentRegistrar.nft()), address(nft));
        assertEq(rentRegistrar.rootNode(), rootNode);
        assertEq(rentRegistrar.yearlyRent(), 0.0001 ether);
        assertEq(rentRegistrar.owner(), deployer);
    }
    
    function testRentPrice() public view {
        assertEq(rentRegistrar.rentPrice(1), 0.0001 ether);
        assertEq(rentRegistrar.rentPrice(2), 0.0002 ether);
        assertEq(rentRegistrar.rentPrice(5), 0.0005 ether);
    }
    
    function testDomainAvailability() public {
        assertTrue(rentRegistrar.isAvailable(testDomainName));
        
        // Register a domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Domain should no longer be available
        assertFalse(rentRegistrar.isAvailable(testDomainName));
        
        // Fast forward past expiration
        vm.warp(block.timestamp + 366 days);
        
        // Domain should be available again
        assertTrue(rentRegistrar.isAvailable(testDomainName));
    }
    
    function testDomainRegistration() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        
        uint256 balanceBefore = address(rentRegistrar).balance;
        
        // Register a domain
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Check payment
        assertEq(address(rentRegistrar).balance, balanceBefore + 0.0001 ether);
        
        // Check domain registration
        (address owner, uint256 expires) = rentRegistrar.domains(testLabel);
        assertEq(owner, user1);
        assertEq(expires, block.timestamp + 365 days);
        
        // Check ENS registry
        assertEq(ens.owner(testNode), user1);
        
        // Check NFT minted
        assertEq(nft.ownerOf(uint256(testLabel)), user1);
    }
    
    function testRegistrationFailsWithInsufficientPayment() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        
        // Try to register with insufficient payment
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.InsufficientPayment.selector, 0.0001 ether, 0.00005 ether));
        rentRegistrar.register{value: 0.00005 ether}(testDomainName, user1, 1, tokenURI);
    }
    
    function testRegistrationFailsWithInvalidDuration() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        
        // Try to register with 0 years
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.InsufficientDuration.selector, 0, 1));
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 0, tokenURI);
    }
    
    function testRegistrationFailsWhenDomainNotAvailable() public {
        // First registration
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Attempt second registration of the same domain
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.DomainNotAvailable.selector, testDomainName));
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user2, 1, tokenURI);
    }
    
    function testDomainRenewal() public {
        // Register domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Check initial expiration
        (,uint256 initialExpires) = rentRegistrar.domains(testLabel);
        
        // Renew domain
        vm.prank(user1);
        rentRegistrar.renew{value: 0.0002 ether}(testDomainName, 2);
        
        // Check updated expiration
        (,uint256 newExpires) = rentRegistrar.domains(testLabel);
        assertEq(newExpires, initialExpires + 2 * 365 days);
    }
    
    function testRenewalFailsWithInsufficientPayment() public {
        // Register domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Try to renew with insufficient payment
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.InsufficientPayment.selector, 0.0001 ether, 0.00005 ether));
        rentRegistrar.renew{value: 0.00005 ether}(testDomainName, 1);
    }
    
    function testRenewalFailsWhenNotOwner() public {
        // Register domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Try to renew from non-owner account
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.NotDomainOwner.selector, testDomainName, user2, user1));
        rentRegistrar.renew{value: 0.0001 ether}(testDomainName, 1);
    }
    
    function testRenewalAfterExpiration() public {
        // Register domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Fast forward past expiration
        vm.warp(block.timestamp + 366 days);
        
        // Renew domain after expiration
        vm.prank(user1);
        rentRegistrar.renew{value: 0.0001 ether}(testDomainName, 1);
        
        // Check domain is now active with new expiration
        (,uint256 expires) = rentRegistrar.domains(testLabel);
        assertEq(expires, block.timestamp + 365 days);
    }
    
    function testDomainOwnershipTransfer() public {
        // Register domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Setup NFT for transfer - directly set approval for all to avoid individual approvals
        vm.startPrank(user1);
        nft.setApprovalForAll(address(rentRegistrar), true);
        
        // Transfer ownership to user2
        rentRegistrar.transferOwnership(testDomainName, user2);
        vm.stopPrank();
        
        // Check updated owner
        (address newOwner,) = rentRegistrar.domains(testLabel);
        assertEq(newOwner, user2);
        
        // Check ENS registry updated
        assertEq(ens.owner(testNode), user2);
        
        // Check NFT transferred
        assertEq(nft.ownerOf(uint256(testLabel)), user2);
    }
    
    function testTransferFailsWhenNotOwner() public {
        // Register domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Try to transfer from non-owner account
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.NotDomainOwner.selector, testDomainName, user2, user1));
        rentRegistrar.transferOwnership(testDomainName, user2);
    }
    
    function testTransferFailsWhenDomainExpired() public {
        // Register domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Fast forward past expiration
        uint256 expiryTime = block.timestamp + 365 days;
        vm.warp(expiryTime + 1);
        
        // Try to transfer expired domain
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.DomainExpired.selector, testDomainName, expiryTime));
        rentRegistrar.transferOwnership(testDomainName, user2);
    }
    
    function testDomainExpiresCheck() public {
        // Register domain
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Check expiration matches expected value
        uint256 expectedExpiry = block.timestamp + 365 days;
        assertEq(rentRegistrar.domainExpires(testDomainName), expectedExpiry);
    }
    
    function testWithdraw() public {
        // Add funds to the contract
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Ensure deployer has some initial balance
        vm.deal(deployer, 1 ether);
        uint256 initialBalance = deployer.balance;
        uint256 contractBalance = address(rentRegistrar).balance;
        
        // Withdraw funds
        vm.prank(deployer);
        rentRegistrar.withdraw();
        
        // Check balances
        assertEq(deployer.balance, initialBalance + contractBalance);
        assertEq(address(rentRegistrar).balance, 0);
    }
    
    function testWithdrawFailsWhenNotOwner() public {
        // Add funds to the contract
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        rentRegistrar.register{value: 0.0001 ether}(testDomainName, user1, 1, tokenURI);
        
        // Try to withdraw from non-owner account
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        rentRegistrar.withdraw();
    }
    
    function testWithdrawFailsWhenNoFunds() public {
        // Try to withdraw when there are no funds
        vm.prank(deployer);
        vm.expectRevert(RentRegistrar.NoFundsToWithdraw.selector);
        rentRegistrar.withdraw();
    }
    
    function testRegistrationWithExcessPayment() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        
        // Register with excess payment
        rentRegistrar.register{value: 0.0002 ether}(testDomainName, user1, 1, tokenURI);
        
        // Check contract balance reflects the full payment
        assertEq(address(rentRegistrar).balance, 0.0002 ether);
    }
    
    function testMultipleDomainsRegistration() public {
        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
        
        // Register first domain
        rentRegistrar.register{value: 0.0001 ether}("domain1", user1, 1, "https://example.com/metadata/domain1");
        
        // Register second domain
        rentRegistrar.register{value: 0.0001 ether}("domain2", user1, 1, "https://example.com/metadata/domain2");
        
        vm.stopPrank();
        
        // Check both domains are registered
        bytes32 label1 = keccak256(bytes("domain1"));
        bytes32 label2 = keccak256(bytes("domain2"));
        
        (address owner1,) = rentRegistrar.domains(label1);
        (address owner2,) = rentRegistrar.domains(label2);
        
        assertEq(owner1, user1);
        assertEq(owner2, user1);
        
        // Check contract balance reflects both payments
        assertEq(address(rentRegistrar).balance, 0.0002 ether);
    }
    
    function testRegistrationFailsWithNonexistentDomain() public {
        // Try to transfer a domain that doesn't exist
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.DomainNotRegistered.selector, "nonexistent"));
        rentRegistrar.transferOwnership("nonexistent", user2);
    }
    
    function testRenewalFailsWithNonexistentDomain() public {
        // Try to renew a domain that doesn't exist
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(RentRegistrar.DomainNotRegistered.selector, "nonexistent"));
        rentRegistrar.renew{value: 0.0001 ether}("nonexistent", 1);
    }
}