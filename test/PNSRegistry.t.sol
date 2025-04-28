// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/core/PNSRegistry.sol";
import "../src/core/PNSPaymentRouter.sol";
import "../src/interfaces/IPNSRegistry.sol";
import "../src/interfaces/IPublicResolver.sol";

/**
 * @title MockPNSRegistry
 * @dev Mock implementation of IPNSRegistry for testing
 */
contract MockPNSRegistry is IPNSRegistry {
    mapping(bytes32 => address) private owners;
    mapping(bytes32 => address) private resolvers;
    mapping(bytes32 => uint64) private ttls;

    constructor() {
        // Set root node owner to this contract
        owners[bytes32(0)] = address(this);
    }

    function setOwner(bytes32 node, address owner) external override {
        owners[node] = owner;
        emit Transfer(node, owner);
    }

    function owner(bytes32 node) external view override returns (address) {
        return owners[node];
    }

    function setResolver(bytes32 node, address resolver) external override {
        resolvers[node] = resolver;
        emit NewResolver(node, resolver);
    }

    function resolver(bytes32 node) external view override returns (address) {
        return resolvers[node];
    }

    function setTTL(bytes32 node, uint64 ttl) external override {
        ttls[node] = ttl;
        emit NewTTL(node, ttl);
    }

    function ttl(bytes32 node) external view override returns (uint64) {
        return ttls[node];
    }

    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external override {
        bytes32 subnode = keccak256(abi.encodePacked(node, label));
        owners[subnode] = owner;
        emit NewOwner(node, label, owner);
    }

    function setRecord(bytes32 node, address owner, address resolver, uint64 ttl) external override {
        owners[node] = owner;
        resolvers[node] = resolver;
        ttls[node] = ttl;
        
        emit Transfer(node, owner);
        emit NewResolver(node, resolver);
        emit NewTTL(node, ttl);
    }
}

/**
 * @title MockPublicResolver
 * @dev Mock implementation of IPublicResolver for testing
 */
contract MockPublicResolver is IPublicResolver {
    mapping(bytes32 => address) private addresses;
    
    // Interface ID for addr(bytes32)
    bytes4 private constant ADDR_INTERFACE_ID = 0x3b3b57de;
    
    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == ADDR_INTERFACE_ID;
    }
    
    function addr(bytes32 node) external view override returns (address) {
        return addresses[node];
    }
    
    // Helper function for testing - not part of the interface
    function setAddr(bytes32 node, address addr) external {
        addresses[node] = addr;
    }
}

/**
 * @title PNSRegistryTest
 * @dev Test contract for verifying ENS namehash implementation
 */
contract PNSRegistryTest is Test {
    // Contracts under test
    MockPNSRegistry internal pnsRegistry;
    PNSPaymentRouter internal router;
    MockPublicResolver internal resolver;
    
    // Test constants
    address private constant TEST_OWNER = address(0x1);
    address private constant TEST_RECIPIENT = address(0x123);
    
    function setUp() public {
        // Deploy mock registry
        pnsRegistry = new MockPNSRegistry();
        
        // Deploy mock resolver
        resolver = new MockPublicResolver();
        
        // Deploy router with mock registry
        vm.prank(TEST_OWNER);
        router = new PNSPaymentRouter(address(pnsRegistry));
    }
    
    function testGetNodeHash() public {
        // Test empty string
        assertEq(router.getNodeHash(""), bytes32(0));
        
        // Test single label
        bytes32 singleLabel = router.getNodeHash("eth");
        assertEq(singleLabel, keccak256(abi.encodePacked(bytes32(0), keccak256(bytes("eth")))));
        
        // Test two labels
        string[] memory labels = new string[](2);
        labels[0] = "eth";
        labels[1] = "alice";
        bytes32 expected = router.computeNamehashFromLabels(labels);
        assertEq(router.getNodeHash("alice.eth"), expected);
        
        // Test three labels
        labels = new string[](3);
        labels[0] = "eth";
        labels[1] = "alice";
        labels[2] = "sub";
        expected = router.computeNamehashFromLabels(labels);
        assertEq(router.getNodeHash("sub.alice.eth"), expected);
    }
    
    function testResolvePNSNameToAddress() public {
        // Register a name
        string memory name = "alice.eth";
        bytes32 node = router.getNodeHash(name);
        
        // Set resolver for the node
        vm.prank(address(pnsRegistry));
        pnsRegistry.setResolver(node, address(resolver));
        
        // Set the address in resolver
        resolver.setAddr(node, TEST_RECIPIENT);
        
        // Test resolution
        address resolved = router.resolvePNSNameToAddress(name, bytes32(0));
        assertEq(resolved, TEST_RECIPIENT);
        
        // Test with pre-calculated node
        resolved = router.resolvePNSNameToAddress(name, node);
        assertEq(resolved, TEST_RECIPIENT);
    }
    
    function testResolvePNSNameToAddressErrors() public {
        // Test empty name
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.resolvePNSNameToAddress("", bytes32(0));
        
        // Test unregistered name
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__ResolverNotSet.selector);
        router.resolvePNSNameToAddress("unregistered.eth", bytes32(0));
        
        // Test invalid resolver
        string memory name = "test.eth";
        bytes32 node = router.getNodeHash(name);
        vm.prank(address(pnsRegistry));
        pnsRegistry.setResolver(node, address(0x123)); // non-resolver address
        
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__ResolverNotSet.selector);
        router.resolvePNSNameToAddress(name, bytes32(0));
    }
    
    function testNamehashMalformed() public {
        // Test node hash mismatch
        string memory name = "alice.eth";
        bytes32 correctNode = router.getNodeHash(name);
        bytes32 incorrectNode = bytes32(uint256(correctNode) + 1); // just a different hash
        
        // Set up resolver
        vm.prank(address(pnsRegistry));
        pnsRegistry.setResolver(correctNode, address(resolver));
        resolver.setAddr(correctNode, TEST_RECIPIENT);
        
        // Should still resolve using correct hash even when incorrect one is provided
        address resolved = router.resolvePNSNameToAddress(name, incorrectNode);
        assertEq(resolved, TEST_RECIPIENT);
    }
    
    function testMultiLevelDomains() public {
        // Test progressively deeper domains
        string memory name1 = "eth";
        string memory name2 = "alice.eth";
        string memory name3 = "sub.alice.eth";
        string memory name4 = "deep.sub.alice.eth";
        
        bytes32 node1 = router.getNodeHash(name1);
        bytes32 node2 = router.getNodeHash(name2);
        bytes32 node3 = router.getNodeHash(name3);
        bytes32 node4 = router.getNodeHash(name4);
        
        // Verify they're all different
        assertTrue(node1 != node2);
        assertTrue(node2 != node3);
        assertTrue(node3 != node4);
        
        // Set resolvers for each
        address resolver1 = address(new MockPublicResolver());
        address resolver2 = address(new MockPublicResolver());
        address resolver3 = address(new MockPublicResolver());
        address resolver4 = address(new MockPublicResolver());
        
        vm.startPrank(address(pnsRegistry));
        pnsRegistry.setResolver(node1, resolver1);
        pnsRegistry.setResolver(node2, resolver2);
        pnsRegistry.setResolver(node3, resolver3);
        pnsRegistry.setResolver(node4, resolver4);
        vm.stopPrank();
        
        // Set addresses
        MockPublicResolver(resolver1).setAddr(node1, address(0x1));
        MockPublicResolver(resolver2).setAddr(node2, address(0x2));
        MockPublicResolver(resolver3).setAddr(node3, address(0x3));
        MockPublicResolver(resolver4).setAddr(node4, address(0x4));
        
        // Verify resolution
        assertEq(router.resolvePNSNameToAddress(name1, bytes32(0)), address(0x1));
        assertEq(router.resolvePNSNameToAddress(name2, bytes32(0)), address(0x2));
        assertEq(router.resolvePNSNameToAddress(name3, bytes32(0)), address(0x3));
        assertEq(router.resolvePNSNameToAddress(name4, bytes32(0)), address(0x4));
    }
}

