// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20Transfer} from "../src/ERC20Transfer.sol";
import {PNSRegistry} from "../src/PNSRegistry.sol";
import {PublicResolver} from "../src/PublicResolver.sol";
import {IPNSRegistry} from "../src/IPNSRegistry.sol";
import {IPublicResolver} from "../src/IPublicResolver.sol";

/**
 * @title ERC20TransferTest
 * @dev Test suite for the ERC20Transfer contract
 */
contract ERC20TransferTest is Test {
    // Constants
    address private constant ADMIN = address(0x1);
    address private constant USER1 = address(0x2);
    address private constant USER2 = address(0x3);
    string private constant TEST_NAME = "test";
    
    // Contract instances
    ERC20Transfer private erc20Transfer;
    PNSRegistry private pnsRegistry;
    PublicResolver private resolver;

    // Events to test
    event TransferToPNS(address indexed sender, bytes32 indexed node, uint256 amount);

    function setUp() public {
        // Deploy contracts as ADMIN
        vm.startPrank(ADMIN);
        
        // Deploy PNS Registry
        pnsRegistry = new PNSRegistry();
        
        // Deploy Public Resolver
        resolver = new PublicResolver(address(pnsRegistry));
        
        // Deploy ERC20Transfer contract
        erc20Transfer = new ERC20Transfer(address(pnsRegistry));
        
        // Set up test node in PNS Registry
        bytes32 rootNode = bytes32(0);
        bytes32 label = keccak256("test");
        
        // Create "test" subnode and set owner to USER1
        pnsRegistry.setSubnodeOwner(rootNode, label, USER1);
        
        // Set resolver for the test node
        vm.stopPrank();
        
        vm.prank(USER1);
        bytes32 TEST_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(TEST_NAME))));
        pnsRegistry.setResolver(TEST_NODE, address(resolver));
        
        vm.stopPrank();
    }

    function test_ContractDeployment() public {
        assertEq(address(erc20Transfer.pnsRegistry()), address(pnsRegistry), "PNS Registry address should match");
    }
    
    function test_TransferToPNS() public {
        // Setup: Set USER2 as the address for TEST_NODE in the resolver
        vm.prank(USER1);
        bytes32 TEST_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(TEST_NAME))));
        resolver.setAddr(TEST_NODE, USER2);
        
        // Get USER2's initial balance
        uint256 initialBalance = USER2.balance;
        
        // Amount to transfer
        uint256 transferAmount = 1 ether;
        
        // Execute transfer to PNS
        vm.deal(address(this), transferAmount);
        vm.expectEmit(true, true, true, true);
        emit TransferToPNS(address(this), TEST_NODE, transferAmount);
        erc20Transfer.transferToPNS{value: transferAmount}(TEST_NAME);
        
        // Verify USER2 received the ETH
        assertEq(USER2.balance, initialBalance + transferAmount, "USER2 should receive the transferred ETH");
    }
    
    function test_RevertWhenNoETHSent() public {
        // Setup resolver
        vm.prank(USER1);
        bytes32 TEST_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(TEST_NAME))));
        resolver.setAddr(TEST_NODE, USER2);
        
        // Attempt to transfer with 0 ETH
        vm.expectRevert(ERC20Transfer.InvalidETHAmount.selector);
        erc20Transfer.transferToPNS{value: 0}(TEST_NAME);
    }
    
    function test_RevertWhenNoResolverSet() public {
        // Create a new node with no resolver
        string memory noResolverNode ="noresolver";
        vm.prank(ADMIN);
        pnsRegistry.setSubnodeOwner(bytes32(0), keccak256("noresolver"), USER1);
        
        // Try to transfer (should fail)
        vm.expectRevert(ERC20Transfer.ResolverNotSet.selector);
        erc20Transfer.transferToPNS{value: 1 ether}(noResolverNode);
    }
    
    function test_RevertWhenNoAddressSet() public {
        // Create a node with resolver but no address set
        string memory noAddrName = "noaddr";
        bytes32 noAddrNode = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(noAddrName))));
        
        vm.startPrank(ADMIN);
        pnsRegistry.setSubnodeOwner(bytes32(0), keccak256("noaddr"), USER1);
        vm.stopPrank();
        
        vm.prank(USER1);
        pnsRegistry.setResolver(noAddrNode, address(resolver));
        
        // Note: We don't set an address in the resolver
        
        // Try to transfer (should fail)
        vm.expectRevert(ERC20Transfer.AddressNotSetInResolver.selector);
        erc20Transfer.transferToPNS{value: 1 ether}(noAddrName);
    }
    
    function test_TransferToMultipleAddresses() public {
        // Setup multiple PNS nodes and addresses
        bytes32[] memory nodes = new bytes32[](3);
        address[] memory recipients = new address[](3);
        string[] memory names = new string[](3);
        
        names[0] = "test";
        names[1] = "test2";
        names[2] = "test3";
        
        bytes32 TEST_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(TEST_NAME))));
        nodes[0] = TEST_NODE;
        nodes[1] = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(names[1]))));
        nodes[2] = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(names[2]))));
        
        recipients[0] = USER2;
        recipients[1] = address(0x4);
        recipients[2] = address(0x5);
        
        // Set up the PNS nodes
        for (uint i = 1; i < 3; i++) {
            bytes32 label = keccak256(bytes(names[i]));
            
            vm.prank(ADMIN);  // Important: ADMIN is the owner of the root node
            pnsRegistry.setSubnodeOwner(bytes32(0), label, USER1);
            
            vm.prank(USER1);
            pnsRegistry.setResolver(nodes[i], address(resolver));
            
            vm.prank(USER1);
            resolver.setAddr(nodes[i], recipients[i]);
        }
        
        // Set address for TEST_NODE
        vm.prank(USER1);
        resolver.setAddr(TEST_NODE, USER2);
        
        // Transfer to each address and verify
        uint256 transferAmount = 0.5 ether;
        for (uint i = 0; i < 3; i++) {
            // Get initial balance
            uint256 initialBalance = recipients[i].balance;
            
            // Transfer ETH
            vm.deal(address(this), transferAmount);
            erc20Transfer.transferToPNS{value: transferAmount}(names[i]);
            
            // Verify balance increased
            assertEq(
                recipients[i].balance, 
                initialBalance + transferAmount, 
                "Recipient should receive the transferred ETH"
            );
        }
    }    
    function test_TransferFailure() public {
        // Create a malicious contract that rejects ETH
        MaliciousReceiver maliciousContract = new MaliciousReceiver();
        
        // Setup the resolver to point to the malicious contract
        vm.prank(USER1);
        bytes32 TEST_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(TEST_NAME))));
        resolver.setAddr(TEST_NODE, address(maliciousContract));
        
        // Try to transfer (should fail)
        vm.expectRevert(ERC20Transfer.ETHTransferFailed.selector);
        erc20Transfer.transferToPNS{value: 1 ether}(TEST_NAME);
    }
    
    // Fallback function to receive ETH
    receive() external payable {}
}

// Helper contract that refuses to accept ETH
contract MaliciousReceiver {
    // Explicitly reject all ETH transfers
    receive() external payable {
        revert("I reject all ETH");
    }
}
