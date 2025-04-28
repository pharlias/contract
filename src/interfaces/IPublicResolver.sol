// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IPublicResolver {
    // External functions
    function setAddr(bytes32 node, address newAddr) external;
    function addr(bytes32 node) external view returns (address);
}
