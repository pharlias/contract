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

    function setOwner(bytes32 node, address newOwner) external override {
        owners[node] = newOwner;
        emit Transfer(node, newOwner);
    }

    function owner(bytes32 node) external view override returns (address) {
        return owners[node];
    }

    function setResolver(bytes32 node, address newResolver) external override {
        resolvers[node] = newResolver;
        emit NewResolver(node, newResolver);
    }

    function resolver(bytes32 node) external view override returns (address) {
        return resolvers[node];
    }

    function setTTL(bytes32 node, uint64 newTTL) external override {
        ttls[node] = newTTL;
        emit NewTTL(node, newTTL);
    }

    function ttl(bytes32 node) external view override returns (uint64) {
        return ttls[node];
    }

    function setSubnodeOwner(bytes32 node, bytes32 label, address newOwner) external override {
        bytes32 subnode = keccak256(abi.encodePacked(node, label));
        owners[subnode] = newOwner;
        emit NewOwner(node, label, newOwner);
    }

    function setRecord(bytes32 node, address newOwner, address newResolver, uint64 newTTL) external override {
        owners[node] = newOwner;
        resolvers[node] = newResolver;
        ttls[node] = newTTL;
        
        emit Transfer(node, newOwner);
        emit NewResolver(node, newResolver);
        emit NewTTL(node, newTTL);
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
    function setAddr(bytes32 node, address newAddr) external {
        addresses[node] = newAddr;
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
    
    function testGetNodeHash() public view {
        // Test empty string
        assertEq(router.getNodeHash(""), bytes32(0));
        
        // Test single label
        bytes32 singleLabel = router.getNodeHash("eth");
        assertEq(singleLabel, keccak256(abi.encodePacked(bytes32(0), keccak256(bytes("eth")))));
        
        // Test two labels - verify different from single label
        bytes32 twoLabels = router.getNodeHash("alice.eth");
        assertTrue(twoLabels != singleLabel);
        
        // Test three labels - verify different from two labels
        bytes32 threeLabels = router.getNodeHash("sub.alice.eth");
        assertTrue(threeLabels != twoLabels);
        
        // Test with hyphen
        bytes32 withHyphen = router.getNodeHash("alice-bob.eth");
        assertTrue(withHyphen != twoLabels); // Should be different from alice.eth
        
        // Test numeric characters
        bytes32 withNumbers = router.getNodeHash("123.eth");
        assertTrue(withNumbers != singleLabel); // Should be different from eth
    }
    
    function testGetNodeHashInvalidCharacters() public {
        // Test invalid characters
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.getNodeHash("alice!.eth");
        
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.getNodeHash("alice@.eth");
        
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.getNodeHash("alice#.eth");
        
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.getNodeHash("alice$.eth");
    }
    
    function testGetNodeHashEdgeCases() public view {
        // Get base hash for alice.eth
        bytes32 baseHash = router.getNodeHash("alice.eth");
        
        // Test consecutive dots - should be treated as one dot
        bytes32 consecutiveDots = router.getNodeHash("alice..eth");
        assertEq(consecutiveDots, baseHash);
        
        // Test leading dot - should be ignored
        bytes32 leadingDot = router.getNodeHash(".alice.eth");
        assertEq(leadingDot, baseHash);
        
        // Test trailing dot - should be ignored
        bytes32 trailingDot = router.getNodeHash("alice.eth.");
        assertEq(trailingDot, baseHash);
    }
    
    function testResolvePNSNameToAddress() public {
        // Register a name
        string memory name = "alice.eth";
        bytes32 node = router.getNodeHash(name);
        
        // Set owner for the node
        vm.prank(address(pnsRegistry));
        pnsRegistry.setOwner(node, TEST_OWNER);
        
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
    
    function testResolvePNSNameToAddressOwnerFallback() public {
        // Register a name with no resolver
        string memory name = "bob.eth";
        bytes32 node = router.getNodeHash(name);
        
        // Set owner only
        vm.prank(address(pnsRegistry));
        pnsRegistry.setOwner(node, TEST_OWNER);
        
        // Should fallback to owner when no resolver is set
        address resolved = router.resolvePNSNameToAddress(name, bytes32(0));
        assertEq(resolved, TEST_OWNER);
        
        // Set resolver but don't set addr
        vm.prank(address(pnsRegistry));
        pnsRegistry.setResolver(node, address(resolver));
        
        // Should fallback to owner when resolver doesn't have addr set
        resolved = router.resolvePNSNameToAddress(name, bytes32(0));
        assertEq(resolved, TEST_OWNER);
    }
    
    function testResolvePNSNameToAddressErrors() public {
        // Test invalid characters in name
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.resolvePNSNameToAddress("alice!.eth", bytes32(0));
        
        // Test unregistered name (no owner)
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.resolvePNSNameToAddress("unregistered.eth", bytes32(0));
    }
    
    function testNamehashMalformed() public {
        // Test node hash mismatch
        string memory name = "alice.eth";
        bytes32 correctNode = router.getNodeHash(name);
        bytes32 incorrectNode = bytes32(uint256(correctNode) + 1); // just a different hash
        
        // Set up owner and resolver
        vm.startPrank(address(pnsRegistry));
        pnsRegistry.setOwner(correctNode, TEST_OWNER);
        pnsRegistry.setResolver(correctNode, address(resolver));
        vm.stopPrank();
        resolver.setAddr(correctNode, TEST_RECIPIENT);

        // Should fail when using incorrect node
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.resolvePNSNameToAddress(name, incorrectNode);
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
        
        // Set up owners and resolvers for each
        address resolver1 = address(new MockPublicResolver());
        address resolver2 = address(new MockPublicResolver());
        address resolver3 = address(new MockPublicResolver());
        address resolver4 = address(new MockPublicResolver());
        
        vm.startPrank(address(pnsRegistry));
        // Set owners first
        pnsRegistry.setOwner(node1, TEST_OWNER);
        pnsRegistry.setOwner(node2, TEST_OWNER);
        pnsRegistry.setOwner(node3, TEST_OWNER);
        pnsRegistry.setOwner(node4, TEST_OWNER);
        
        // Then set resolvers
        pnsRegistry.setResolver(node1, resolver1);
        pnsRegistry.setResolver(node2, resolver2);
        pnsRegistry.setResolver(node3, resolver3);
        pnsRegistry.setResolver(node4, resolver4);
        vm.stopPrank();
        
        // Set addresses in resolvers
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

    function testDebugPNSResolution() public {
        // Set up test data
        string memory name = "alice.eth";
        bytes32 node = router.getNodeHash(name);
        
        // Set owner and resolver
        vm.startPrank(address(pnsRegistry));
        pnsRegistry.setOwner(node, TEST_OWNER);
        pnsRegistry.setResolver(node, address(resolver));
        vm.stopPrank();
        resolver.setAddr(node, TEST_RECIPIENT);
        
        // Test debug resolution
        (
            bytes32 nodeHash,
            address ownerAddress,
            address resolverAddress,
            address resolverResult,
            address finalAddress
        ) = router.debugPNSResolution(name);
        
        // Verify results
        assertEq(nodeHash, node);
        assertEq(ownerAddress, TEST_OWNER);
        assertEq(resolverAddress, address(resolver));
        assertEq(resolverResult, TEST_RECIPIENT);
        assertEq(finalAddress, TEST_RECIPIENT);
    }

    function testDebugPNSResolutionNoResolver() public {
        string memory name = "alice.eth";
        bytes32 node = router.getNodeHash(name);
        
        // Only set owner, no resolver
        vm.prank(address(pnsRegistry));
        pnsRegistry.setOwner(node, TEST_OWNER);
        
        // Test debug resolution
        (
            bytes32 nodeHash,
            address ownerAddress,
            address resolverAddress,
            address resolverResult,
            address finalAddress
        ) = router.debugPNSResolution(name);
        
        // Verify fallback to owner
        assertEq(nodeHash, node);
        assertEq(ownerAddress, TEST_OWNER);
        assertEq(resolverAddress, address(0));
        assertEq(resolverResult, address(0));
        assertEq(finalAddress, TEST_OWNER);
    }

    function testDebugPNSResolutionUnregistered() public view {
        string memory name = "unregistered.eth";
        
        // Test debug resolution of unregistered name
        (
            ,
            address ownerAddress,
            address resolverAddress,
            address resolverResult,
            address finalAddress
        ) = router.debugPNSResolution(name);
        
        // Verify all addresses are zero
        assertEq(ownerAddress, address(0));
        assertEq(resolverAddress, address(0));
        assertEq(resolverResult, address(0));
        assertEq(finalAddress, address(0));
    }

    function testDebugPNSResolutionResolverNoAddr() public {
        string memory name = "alice.eth";
        bytes32 node = router.getNodeHash(name);
        
        // Set up with resolver but no address
        vm.startPrank(address(pnsRegistry));
        pnsRegistry.setOwner(node, TEST_OWNER);
        pnsRegistry.setResolver(node, address(resolver));
        vm.stopPrank();
        // Deliberately not setting resolver address
        
        // Test debug resolution
        (
            bytes32 nodeHash,
            address ownerAddress,
            address resolverAddress,
            address resolverResult,
            address finalAddress
        ) = router.debugPNSResolution(name);
        
        // Verify fallback to owner when resolver has no address
        assertEq(nodeHash, node);
        assertEq(ownerAddress, TEST_OWNER);
        assertEq(resolverAddress, address(resolver));
        assertEq(resolverResult, address(0));
        assertEq(finalAddress, TEST_OWNER);
    }

    function testDebugPNSResolutionInvalidName() public {
        string memory name = "alice!.eth";
        
        // Test debug resolution of invalid name
        vm.expectRevert(PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector);
        router.debugPNSResolution(name);
    }
}
