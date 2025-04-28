// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./IPNSRegistry.sol";
import "./IPublicResolver.sol";


contract ERC20Transfer {
    IPNSRegistry public pnsRegistry;

    mapping(address => uint256) public interactionCount;

    event TransferToPNS(address indexed sender, bytes32 indexed node, uint256 amount);

    // Custom errors for better gas efficiency and clarity
    error InvalidETHAmount();
    error ResolverNotSet();
    error AddressNotSetInResolver();
    error ETHTransferFailed();
    error InvalidName();

    constructor(address _pnsRegistry) {
        pnsRegistry = IPNSRegistry(_pnsRegistry);
    }

    function transferToPNS(string memory name) external payable {
        if (bytes(name).length == 0) revert InvalidName();
        if (msg.value == 0) revert InvalidETHAmount();
        
        bytes32 node = keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(name))));

        address resolverAddress = pnsRegistry.resolver(node);
        if (resolverAddress == address(0)) revert ResolverNotSet();

        address walletAddress = IPublicResolver(resolverAddress).addr(node);
        if (walletAddress == address(0)) revert AddressNotSetInResolver();

        (bool success, ) = walletAddress.call{value: msg.value}("");
        if (!success) revert ETHTransferFailed();

        interactionCount[msg.sender] += 1;

        emit TransferToPNS(msg.sender, node, msg.value);
    }
}
