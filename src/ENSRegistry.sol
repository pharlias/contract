// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;


contract ENSRegistry {
    struct Record {
        address owner;
        address resolver;
        uint64 ttl;
    }

    mapping(bytes32 => Record) records;

    function setOwner(bytes32 node, address newOwner) external {
        require(msg.sender == records[node].owner, "Not authorized");
        records[node].owner = newOwner;
    }

    function owner(bytes32 node) external view returns (address) {
        return records[node].owner;
    }

    function setResolver(bytes32 node, address newResolver) external {
        require(msg.sender == records[node].owner, "Not authorized");
        records[node].resolver = newResolver;
    }

    function resolver(bytes32 node) external view returns (address) {
        return records[node].resolver;
    }
}
