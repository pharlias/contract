// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../structs/PNSRegistryStructs.sol";

interface IPNSRegistry {
    // Use shared struct from PNSRegistryStructs

    // Events
    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);
    event Transfer(bytes32 indexed node, address owner);
    event NewResolver(bytes32 indexed node, address resolver);
    event NewTTL(bytes32 indexed node, uint64 ttl);

    // External functions
    function setOwner(bytes32 node, address newOwner) external;
    function owner(bytes32 node) external view returns (address);
    function setResolver(bytes32 node, address newResolver) external;
    function resolver(bytes32 node) external view returns (address);
    function setTTL(bytes32 node, uint64 newTTL) external;
    function ttl(bytes32 node) external view returns (uint64);
    function setSubnodeOwner(bytes32 node, bytes32 label, address newOwner) external;
    function setRecord(bytes32 node, address newOwner, address newResolver, uint64 newTTL) external;
}
