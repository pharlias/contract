// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title PNSRegistry
 * @dev Implementation of the ENS registry system
 */
contract PNSRegistry is Ownable {
    struct Record {
        address owner;
        address resolver;
        uint64 ttl;
    }

    // Events from ENS standard
    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);
    event Transfer(bytes32 indexed node, address owner);
    event NewResolver(bytes32 indexed node, address resolver);
    event NewTTL(bytes32 indexed node, uint64 ttl);

    mapping(bytes32 => Record) records;

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
}
