// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "../structs/PNSRegistryStructs.sol";
import "../interfaces/IPNSRegistry.sol";

/**
 * @title PNSRegistry
 * @dev Implementation of the ENS registry system
 */
contract PNSRegistry is Ownable, IPNSRegistry {
    // Events are inherited from IPNSRegistry interface

    mapping(bytes32 => PNSRegistryStructs.Record) records;

    constructor() Ownable(msg.sender) {
        // Initialize root node (zero bytes) to the contract deployer
        records[bytes32(0)].owner = msg.sender;
    }

    /**
     * @dev Sets the owner of a node
     * @param node The node to update
     * @param newOwner The address of the new owner
     */
    function setOwner(bytes32 node, address newOwner) external {
        require(
            msg.sender == records[node].owner || msg.sender == owner(),
            "Not authorized"
        );
        _setOwner(node, newOwner);
    }

    /**
     * @dev Gets the owner of a node
     * @param node The node to query
     * @return The address of the owner
     */
    function owner(bytes32 node) external view returns (address) {
        return records[node].owner;
    }

    /**
     * @dev Sets the resolver for a node
     * @param node The node to update
     * @param newResolver The address of the new resolver
     */
    function setResolver(bytes32 node, address newResolver) external {
        require(
            msg.sender == records[node].owner || msg.sender == owner(),
            "Not authorized"
        );
        records[node].resolver = newResolver;
        emit NewResolver(node, newResolver);
    }

    /**
     * @dev Gets the resolver for a node
     * @param node The node to query
     * @return The address of the resolver
     */
    function resolver(bytes32 node) external view returns (address) {
        return records[node].resolver;
    }

    /**
     * @dev Sets the TTL for a node
     * @param node The node to update
     * @param newTTL The new TTL value
     */
    function setTTL(bytes32 node, uint64 newTTL) external {
        require(
            msg.sender == records[node].owner || msg.sender == owner(),
            "Not authorized"
        );
        records[node].ttl = newTTL;
        emit NewTTL(node, newTTL);
    }

    /**
     * @dev Gets the TTL of a node
     * @param node The node to query
     * @return The TTL of the node
     */
    function ttl(bytes32 node) external view returns (uint64) {
        return records[node].ttl;
    }

    /**
     * @dev Creates a new subnode and sets its owner
     * @param node The parent node
     * @param label The hash of the label specifying the subnode
     * @param newOwner The address of the new owner
     */
    function setSubnodeOwner(
        bytes32 node,
        bytes32 label,
        address newOwner
    ) external {
        require(
            msg.sender == records[node].owner || msg.sender == owner(),
            "Not authorized"
        );

        bytes32 subnode = keccak256(abi.encodePacked(node, label));
        _setOwner(subnode, newOwner);
        emit NewOwner(node, label, newOwner);
    }

    /**
     * @dev Sets the record for a node
     * @param node The node to update
     * @param newOwner The address of the new owner
     * @param newResolver The address of the new resolver
     * @param newTTL The new TTL value
     */
    function setRecord(
        bytes32 node,
        address newOwner,
        address newResolver,
        uint64 newTTL
    ) external {
        require(
            msg.sender == records[node].owner || msg.sender == owner(),
            "Not authorized"
        );

        _setOwner(node, newOwner);
        records[node].resolver = newResolver;
        records[node].ttl = newTTL;

        emit NewResolver(node, newResolver);
        emit NewTTL(node, newTTL);
    }

    /**
     * @dev Internal function to set a node's owner
     * @param node The node to update
     * @param newOwner The address of the new owner
     */
    function _setOwner(bytes32 node, address newOwner) internal {
        records[node].owner = newOwner;
        emit Transfer(node, newOwner);
    }

    /**
     * @dev Computes the namehash of a given string
     * @param name The name to hash
     * @return The namehash of the name
     * @notice This function implements the namehash algorithm as specified in EIP-137
     * The algorithm recursively hashes components of the name, starting from the right
     */
    function getNodeHash(string calldata name) public pure returns (bytes32) {
        bytes32 node = 0;

        // Handle empty name case early to save gas
        bytes calldata nameParts = bytes(name);
        if (nameParts.length == 0) {
            return node;
        }

        // Validate characters with optimized range checks
        for (uint i = 0; i < nameParts.length; i++) {
            bytes1 char = nameParts[i];
            // Optimized character validation - combined checks to reduce gas
            bool validChar = (// Alphanumeric: 0-9, A-Z, a-z
            (char >= 0x30 && char <= 0x39) ||
                (char >= 0x41 && char <= 0x5A) ||
                (char >= 0x61 && char <= 0x7A) ||
                // Special characters: hyphen and dot
                char == 0x2D ||
                char == 0x2E);
            require(validChar, "Invalid character in domain name");
        }

        // Process labels from right to left with minimal memory allocations
        int length = int(nameParts.length);
        uint lastDot = uint(length);

        // Single pass through the string
        for (int i = length - 1; i >= 0; i--) {
            uint currentPos = uint(i);

            if (nameParts[currentPos] == ".") {
                // Skip empty labels (consecutive dots)
                if (lastDot == currentPos + 1) {
                    lastDot = currentPos;
                    continue;
                }

                // Instead of creating a full copy, hash the label directly from the original string
                bytes32 labelHash = keccak256(
                    abi.encodePacked(bytes(nameParts[currentPos + 1:lastDot]))
                );

                // Apply namehash algorithm: node = keccak256(node + keccak256(label))
                node = keccak256(abi.encodePacked(node, labelHash));
                lastDot = currentPos;
            } else if (i == 0) {
                // Handle the leftmost label efficiently
                bytes32 labelHash = keccak256(
                    abi.encodePacked(bytes(nameParts[0:lastDot]))
                );

                // Apply namehash algorithm for the final label
                node = keccak256(abi.encodePacked(node, labelHash));
            }
        }

        return node;
    }
}
