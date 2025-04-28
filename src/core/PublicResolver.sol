// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../interfaces/IPNSRegistry.sol";
import "../interfaces/IPublicResolver.sol";

contract PublicResolver is IPublicResolver {
    IPNSRegistry public pnsRegistry;

    mapping(bytes32 => address) public addresses;

    constructor(address _pnsRegistry) {
        pnsRegistry = IPNSRegistry(_pnsRegistry);
    }

    function setAddr(bytes32 node, address newAddr) external {
        require(
            msg.sender == pnsRegistry.owner(node),
            "Not authorized"
        );
        addresses[node] = newAddr;
    }

    function addr(bytes32 node) external view returns (address) {
        return addresses[node];
    }
}

