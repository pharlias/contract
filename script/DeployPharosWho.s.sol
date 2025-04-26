// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/ENSRegistry.sol";
import "../src/PublicResolver.sol";
import "../src/NFTRegistrar.sol";
import "../src/RentRegistrar.sol";

contract DeployPharosWho is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy base contracts
        ENSRegistry ens = new ENSRegistry();
        console.log("ENSRegistry deployed at:", address(ens));

        PublicResolver resolver = new PublicResolver();
        console.log("PublicResolver deployed at:", address(resolver));

        NFTRegistrar nft = new NFTRegistrar();
        console.log("NFTRegistrar deployed at:", address(nft));

        // Prepare node structure
        bytes32 emptyNode = bytes32(0);
        bytes32 pharosLabel = keccak256(bytes("pharos"));
        bytes32 rootNode = keccak256(abi.encodePacked(emptyNode, pharosLabel));

        // Create pharos node under root node and set the deployer as the owner
        // This allows the RentRegistrar to verify ownership in its constructor
        address deployer = vm.addr(deployerPrivateKey);
        ens.setSubnodeOwner(emptyNode, pharosLabel, deployer);
        console.log("Pharos subnode created and owned by deployer");

        // Deploy RentRegistrar - now the deployer owns the rootNode
        RentRegistrar rent = new RentRegistrar(
            ens,
            nft,
            rootNode
        );
        console.log("RentRegistrar deployed at:", address(rent));

        // Transfer ownership to RentRegistrar
        ens.setOwner(rootNode, address(rent));
        console.log("Root node ownership transferred to RentRegistrar");

        nft.transferOwnership(address(rent));
        console.log("NFTRegistrar ownership transferred to RentRegistrar");

        vm.stopBroadcast();
    }
}