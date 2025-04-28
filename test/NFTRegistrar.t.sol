// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/core/NFTRegistrar.sol";

contract NFTRegistrarTest is Test {
    // Events from the contract to check emissions
    event TokenMinted(
        address indexed to,
        uint256 indexed tokenId,
        string tokenURI,
        string domainName
    );
    event TokenBurned(
        uint256 indexed tokenId,
        address indexed previousOwner,
        string domainName
    );
    event DomainNameRegistered(uint256 indexed tokenId, string domainName);

    NFTRegistrar private registrar;
    address private owner;
    address private user;

    // Test values
    uint256 private constant TOKEN_ID = 123456789;
    string private constant TOKEN_URI =
        "https://metadata.example.com/token/123456789";
    string private constant DOMAIN_NAME = "example.eth";

    function setUp() public {
        // Set up accounts
        owner = address(this);
        user = address(0x1);
        vm.startPrank(owner);

        // Deploy contract
        registrar = new NFTRegistrar();

        // Fund the user account for testing
        vm.deal(user, 1 ether);

        vm.stopPrank();
    }

    // Test 1: Successful minting with domain name storage
    function testMintWithDomainName() public {
        vm.startPrank(owner);

        // Expect the events to be emitted
        vm.expectEmit(true, true, false, true);
        emit DomainNameRegistered(TOKEN_ID, DOMAIN_NAME);

        vm.expectEmit(true, true, false, true);
        emit TokenMinted(user, TOKEN_ID, TOKEN_URI, DOMAIN_NAME);

        // Mint the token
        bool success = registrar.mint(user, TOKEN_ID, TOKEN_URI, DOMAIN_NAME);

        // Assertions
        assertTrue(success, "Mint should succeed");
        assertEq(
            registrar.ownerOf(TOKEN_ID),
            user,
            "User should own the token"
        );
        assertEq(
            registrar.tokenURI(TOKEN_ID),
            TOKEN_URI,
            "Token URI should match"
        );

        vm.stopPrank();
    }

    // Test 2: Retrieving domain names
    function testGetDomainName() public {
        vm.startPrank(owner);

        // Mint the token first
        registrar.mint(user, TOKEN_ID, TOKEN_URI, DOMAIN_NAME);

        // Get the domain name
        string memory retrievedDomainName = registrar.getDomainName(TOKEN_ID);

        // Assertion
        assertEq(
            retrievedDomainName,
            DOMAIN_NAME,
            "Retrieved domain name should match the original"
        );

        vm.stopPrank();
    }

    // Test 3.1: Error case - Non-existent token
    function test_RevertWhen_GettingNonExistentToken() public {
        // This should revert with NFTRegistrar__TokenDoesNotExist
        uint256 nonExistentTokenId = 999;

        // Use expectRevert to check for revert
        vm.expectRevert();
        registrar.getDomainName(nonExistentTokenId);
    }

    // Test 3.2: Error case - Empty domain name during mint
    function test_RevertWhen_MintingWithEmptyDomainName() public {
        vm.startPrank(owner);

        // This should revert with NFTRegistrar__EmptyDomainName
        vm.expectRevert();
        registrar.mint(user, TOKEN_ID, TOKEN_URI, "");

        vm.stopPrank();
    }

    // Test 4: Domain name cleanup after burning
    function testBurnClearsDomainsName() public {
        vm.startPrank(owner);

        // Mint the token first
        registrar.mint(user, TOKEN_ID, TOKEN_URI, DOMAIN_NAME);

        // Expect the TokenBurned event with the domain name
        vm.expectEmit(true, true, false, true);
        emit TokenBurned(TOKEN_ID, user, DOMAIN_NAME);

        // Burn the token
        bool success = registrar.burn(TOKEN_ID);

        // Assertions
        assertTrue(success, "Burn should succeed");

        // Try to get the domain name (should fail as token is burned)
        vm.expectRevert();
        registrar.getDomainName(TOKEN_ID);

        vm.stopPrank();
    }

    // Test 5: Proper event emissions
    function testEventEmissions() public {
        vm.startPrank(owner);

        // Test DomainNameRegistered event
        vm.expectEmit(true, true, false, true);
        emit DomainNameRegistered(TOKEN_ID, DOMAIN_NAME);

        // Test TokenMinted event
        vm.expectEmit(true, true, false, true);
        emit TokenMinted(user, TOKEN_ID, TOKEN_URI, DOMAIN_NAME);

        // Mint the token
        registrar.mint(user, TOKEN_ID, TOKEN_URI, DOMAIN_NAME);

        // Test TokenBurned event
        vm.expectEmit(true, true, false, true);
        emit TokenBurned(TOKEN_ID, user, DOMAIN_NAME);

        // Burn the token
        registrar.burn(TOKEN_ID);

        vm.stopPrank();
    }

    // Test 6: Multiple tokens with different domain names
    function testMultipleDomainNames() public {
        vm.startPrank(owner);

        // Mint multiple tokens with different domain names
        string memory domain1 = "example1.eth";
        string memory domain2 = "example2.eth";
        uint256 tokenId1 = 111;
        uint256 tokenId2 = 222;

        registrar.mint(user, tokenId1, TOKEN_URI, domain1);
        registrar.mint(user, tokenId2, TOKEN_URI, domain2);

        // Retrieve and verify domain names
        string memory retrievedDomain1 = registrar.getDomainName(tokenId1);
        string memory retrievedDomain2 = registrar.getDomainName(tokenId2);

        // Assertions
        assertEq(retrievedDomain1, domain1, "First domain name should match");
        assertEq(retrievedDomain2, domain2, "Second domain name should match");

        vm.stopPrank();
    }
}
