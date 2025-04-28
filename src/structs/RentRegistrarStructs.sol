// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title RentRegistrarStructs
 * @dev Shared structs for the Rent Registrar system
 */
library RentRegistrarStructs {
    /**
     * @dev Domain ownership and expiry information
     * @param owner Address of the domain owner
     * @param expires Timestamp when domain registration expires
     */
    struct Domain {
        address owner;
        uint256 expires;
    }
}

