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

        ENSRegistry ens = new ENSRegistry();
        console.log("ENSRegistry deployed at:", address(ens));

        PublicResolver resolver = new PublicResolver();
        console.log("PublicResolver deployed at:", address(resolver));

        NFTRegistrar nft = new NFTRegistrar();
        console.log("NFTRegistrar deployed at:", address(nft));

        bytes32 rootNode = keccak256(abi.encodePacked("pharos"));

        RentRegistrar rent = new RentRegistrar(ens, nft, rootNode);
        console.log("RentRegistrar deployed at:", address(rent));

        nft.transferOwnership(address(rent));
        console.log("NFTRegistrar ownership transferred to RentRegistrar");

        vm.stopBroadcast();
    }
}
