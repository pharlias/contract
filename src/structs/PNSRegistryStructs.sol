// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/**
 * @title PNSRegistryStructs
 * @dev Shared structs for the PNS Registry system
 */
library PNSRegistryStructs {
    struct Record {
        address owner;
        address resolver;
        uint64 ttl;
    }
}

