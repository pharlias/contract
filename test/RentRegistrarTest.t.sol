// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/ENSRegistry.sol";
import "../src/PublicResolver.sol";
import "../src/NFTRegistrar.sol";
import "../src/RentRegistrar.sol";

contract RentRegistrarTest is Test {
    ENSRegistry ens;
    PublicResolver resolver;
    NFTRegistrar nft;
    RentRegistrar rent;

    address alice = address(0x1);
    address bob = address(0x2);
    bytes32 rootNode = keccak256("pharos");

    function setUp() public {
        // Deploy contracts
        ens = new ENSRegistry();
        nft = new NFTRegistrar();
        resolver = new PublicResolver();
        rent = new RentRegistrar(ens, nft, rootNode);

        // Transfer ownership of NFTRegistrar to RentRegistrar
        nft.transferOwnership(address(rent));

        // Give Alice some ETH
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function testRegisterDomain() public {
        vm.startPrank(alice);

        string memory domainName = "alice";
        bytes32 label = keccak256(bytes(domainName));
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));
        string memory tokenURI = "ipfs://alice-uri";

        uint256 duration = 2;
        uint256 price = rent.rentPrice(duration);
        console.log("Price:", price);

        rent.register{value: price}(domainName, alice, duration, tokenURI);

        // ENS owner set correctly
        // assertEq(ens.owner(node), alice);

        // // Domain stored correctly
        // (, uint256 expires) = rent.domains(label);
        // assertGt(expires, block.timestamp);

        // // NFT minted to alice
        // assertEq(nft.ownerOf(uint256(label)), alice);

        vm.stopPrank();
    }

    function testRenewDomain() public {
        vm.startPrank(alice);

        string memory domainName = "alice";
        bytes32 label = keccak256(bytes(domainName));
        string memory tokenURI = "ipfs://alice-uri";
        rent.register{value: rent.rentPrice(1)}(domainName, alice, 1, tokenURI);

        uint256 before = rent.domainExpires(domainName);

        skip(1 days);
        rent.renew{value: rent.rentPrice(1)}(domainName, 1);

        uint256 afterRenew = rent.domainExpires(domainName);
        assertGt(afterRenew, before);

        vm.stopPrank();
    }

    function testTransferOwnership() public {
        vm.startPrank(alice);

        string memory domainName = "alice";
        bytes32 label = keccak256(bytes(domainName));
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));
        string memory tokenURI = "ipfs://alice-uri";

        rent.register{value: rent.rentPrice(1)}(domainName, alice, 1, tokenURI);

        // Approve rent registrar to transfer NFT
        nft.approve(address(rent), uint256(label));
        rent.transferOwnership(domainName, bob);

        assertEq(ens.owner(node), bob);
        assertEq(nft.ownerOf(uint256(label)), bob);
        vm.stopPrank();
    }

    function testWithdraw() public {
        address owner = rent.owner();
        vm.startPrank(owner);

        vm.deal(address(rent), 1 ether);

        address payable receiver = payable(vm.addr(99));
        uint256 before = receiver.balance;

        rent.withdraw(receiver);
        assertGt(receiver.balance, before);

        vm.stopPrank();
    }

    function testFailUnauthorizedRegister() public {
        // Trying to register without paying should fail
        vm.startPrank(alice);
        string memory domainName = "unauthorized";
        string memory tokenURI = "ipfs://fail";

        rent.register(domainName, alice, 1, tokenURI);
        vm.stopPrank();
    }

    function testFailUnauthorizedTransfer() public {
        vm.startPrank(alice);

        string memory domainName = "test";
        string memory tokenURI = "ipfs://test";
        rent.register{value: rent.rentPrice(1)}(domainName, alice, 1, tokenURI);

        // Bob tries to transfer
        vm.stopPrank();
        vm.startPrank(bob);
        rent.transferOwnership(domainName, bob);
        vm.stopPrank();
    }
}
