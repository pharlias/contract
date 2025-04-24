// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./NFTRegistrar.sol";
import "./ENSRegistry.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";


contract RentRegistrar is Ownable{
    ENSRegistry public ens;
    NFTRegistrar public nft;
    bytes32 public rootNode;
    uint256 public yearlyRent = 0.0001 ether;

    struct Domain {
        address owner;
        uint256 expires;
    }

    mapping(bytes32 => Domain) public domains;

    constructor(ENSRegistry _ens, NFTRegistrar _nft, bytes32 _rootNode) Ownable(msg.sender) {
        ens = _ens;
        nft = _nft;
        rootNode = _rootNode;
    }

    function rentPrice(uint256 numYears) public view returns (uint256) {
        return yearlyRent * numYears;
    }

    function isAvailable(string memory name) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        Domain memory domain = domains[label];
        return domain.expires < block.timestamp;
    }

    function register(string memory name, address owner, uint256 durationInYears, string memory tokenURI) external payable {
        require(durationInYears >= 1, "Min 1 year");
        require(isAvailable(name), "Domain not available");
        require(msg.value == rentPrice(durationInYears), "Insufficient payment");

        bytes32 label = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));
        uint256 expires = block.timestamp + durationInYears * 365 days;

        domains[label] = Domain(owner, expires);
        ens.setOwner(node, owner);

        // Mint NFT as proof of domain ownership
        uint256 tokenId = uint256(label);
        nft.mint(owner, tokenId, tokenURI);
    }

    function renew(string memory name, uint256 additionalYears) external payable {
        require(domains[keccak256(bytes(name))].owner != address(0), "Domain not registered");
        require(msg.sender == domains[keccak256(bytes(name))].owner, "Not domain owner");
        require(msg.value >= rentPrice(additionalYears), "Insufficient payment");

        bytes32 label = keccak256(bytes(name));
        Domain storage domain = domains[label];

        if (domain.expires < block.timestamp) {
            domain.expires = block.timestamp + additionalYears * 365 days;
        } else {
            domain.expires += additionalYears * 365 days;
        }
    }

    function transferOwnership(string memory name, address newOwner) external {
        require(msg.sender == domains[keccak256(bytes(name))].owner, "Not owner");

        bytes32 label = keccak256(bytes(name));
        Domain storage domain = domains[label];

        domain.owner = newOwner;
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));
        ens.setOwner(node, newOwner);

        uint256 tokenId = uint256(label);
        nft.safeTransferFrom(msg.sender, newOwner, tokenId);
    }

    function domainExpires(string memory name) external view returns (uint256) {
        return domains[keccak256(bytes(name))].expires;
    }

    function withdraw(address withdrawAddress) external onlyOwner {
        payable(withdrawAddress).transfer(address(this).balance);
    }
}
