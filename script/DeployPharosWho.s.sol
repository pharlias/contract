// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/core/PNSRegistry.sol";
import "../src/core/PublicResolver.sol";
import "../src/core/NFTRegistrar.sol";
import "../src/core/RentRegistrar.sol";
import "../src/core/PNSPaymentRouter.sol";

contract DeployPharosWho is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy base contracts
        PNSRegistry pns = new PNSRegistry();
        console.log("PNSRegistry deployed at:", address(pns));

        PublicResolver resolver = new PublicResolver(address(pns));
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
        pns.setSubnodeOwner(emptyNode, pharosLabel, deployer);
        console.log("Pharos subnode created and owned by deployer");

        // Deploy RentRegistrar - now the deployer owns the rootNode
        RentRegistrar rent = new RentRegistrar(
            pns,
            nft,
            rootNode
        );
        console.log("RentRegistrar deployed at:", address(rent));

        // Deploy PNSPaymentRouter
        PNSPaymentRouter paymentRouter = new PNSPaymentRouter(address(pns));
        console.log("PNSPaymentRouter deployed at:", address(paymentRouter));

        // Transfer ownership to RentRegistrar
        pns.setOwner(rootNode, address(rent));
        console.log("Root node ownership transferred to RentRegistrar");

        nft.transferOwnership(address(rent));
        console.log("NFTRegistrar ownership transferred to RentRegistrar");

        vm.stopBroadcast();
    }
}