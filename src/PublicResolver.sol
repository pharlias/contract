// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;


contract PublicResolver {
    mapping(bytes32 => address) addresses;

    function setAddr(bytes32 node, address newAddr) external {
        addresses[node] = newAddr;
    }

    function addr(bytes32 node) external view returns (address) {
        return addresses[node];
    }
}
