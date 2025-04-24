// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./NFTRegistrar.sol";
import "./ENSRegistry.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract RentRegistrar is Ownable {
    // Custom errors for better gas efficiency and error reporting
    error InvalidRegistryAddress();
    error InvalidNFTRegistrarAddress();
    error InvalidRootNode();
    error InsufficientDuration(uint256 provided, uint256 minimum);
    error DomainNotAvailable(string name);
    error InsufficientPayment(uint256 required, uint256 provided);
    error DomainNotRegistered(string name);
    error NotDomainOwner(string name, address caller, address owner);
    error NoFundsToWithdraw();
    error TransferFailed();
    error NFTMintFailed(uint256 tokenId);
    error NFTBurnFailed(uint256 tokenId);
    error DomainExpired(string name, uint256 expiry);
    ENSRegistry public ens;
    NFTRegistrar public nft;
    bytes32 public rootNode;
    uint256 public yearlyRent = 0.0001 ether;

    event DomainRegistered(
        string name,
        address owner,
        uint256 expires,
        uint256 tokenId
    );
    event DomainRenewed(string name, address owner, uint256 newExpiry);
    event DomainTransferred(
        string name,
        address from,
        address to,
        uint256 tokenId
    );
    event FundsWithdrawn(address owner, uint256 amount);

    struct Domain {
        address owner;
        uint256 expires;
    }

    mapping(bytes32 => Domain) public domains;

    constructor(
        ENSRegistry _ens,
        NFTRegistrar _nft,
        bytes32 _rootNode
    ) Ownable(msg.sender) {
        if (address(_ens) == address(0)) {
            revert InvalidRegistryAddress();
        }
        if (address(_nft) == address(0)) {
            revert InvalidNFTRegistrarAddress();
        }
        if (_rootNode == bytes32(0)) {
            revert InvalidRootNode();
        }
        
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

    function register(
        string memory name,
        address owner,
        uint256 durationInYears,
        string memory tokenURI
    ) external payable {
        if (durationInYears < 1) {
            revert InsufficientDuration(durationInYears, 1);
        }
        
        bytes32 label = keccak256(bytes(name));
        
        if (!isAvailable(name)) {
            revert DomainNotAvailable(name);
        }

        uint256 price = rentPrice(durationInYears);
        if (msg.value < price) {
            revert InsufficientPayment(price, msg.value);
        }

        bytes32 node = keccak256(abi.encodePacked(rootNode, label));
        uint256 expires = block.timestamp + durationInYears * 365 days;

        domains[label] = Domain(owner, expires);
        ens.setOwner(node, owner);

        uint256 tokenId = uint256(label);
        bool success = nft.mint(owner, tokenId, tokenURI);
        if (!success) {
            revert NFTMintFailed(tokenId);
        }

        emit DomainRegistered(name, owner, expires, tokenId);
    }

    function renew(
        string memory name,
        uint256 additionalYears
    ) external payable {
        bytes32 label = keccak256(bytes(name));
        Domain storage domain = domains[label];
        
        if (domain.owner == address(0)) {
            revert DomainNotRegistered(name);
        }
        
        if (msg.sender != domain.owner) {
            revert NotDomainOwner(name, msg.sender, domain.owner);
        }

        uint256 price = rentPrice(additionalYears);
        if (msg.value < price) {
            revert InsufficientPayment(price, msg.value);
        }

        if (domain.expires < block.timestamp) {
            domain.expires = block.timestamp + additionalYears * 365 days;
        } else {
            domain.expires += additionalYears * 365 days;
        }

        emit DomainRenewed(name, domain.owner, domain.expires);
    }

    function transferOwnership(string memory name, address newOwner) external {
        bytes32 label = keccak256(bytes(name));
        Domain storage domain = domains[label];

        if (domain.owner == address(0)) {
            revert DomainNotRegistered(name);
        }
        
        if (msg.sender != domain.owner) {
            revert NotDomainOwner(name, msg.sender, domain.owner);
        }
        
        if (domain.expires < block.timestamp) {
            revert DomainExpired(name, domain.expires);
        }

        uint256 tokenId = uint256(label);
        string memory uri = nft.tokenURI(tokenId);

        domain.owner = newOwner;

        bytes32 node = keccak256(abi.encodePacked(rootNode, label));
        ens.setOwner(node, newOwner);

        bool burnSuccess = nft.burn(tokenId);
        if (!burnSuccess) {
            revert NFTBurnFailed(tokenId);
        }

        bool mintSuccess = nft.mint(newOwner, tokenId, uri);
        if (!mintSuccess) {
            revert NFTMintFailed(tokenId);
        }

        emit DomainTransferred(name, msg.sender, newOwner, tokenId);
    }

    function domainExpires(string memory name) external view returns (uint256) {
        return domains[keccak256(bytes(name))].expires;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            revert NoFundsToWithdraw();
        }
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) {
            revert TransferFailed();
        }

        emit FundsWithdrawn(owner(), balance);
    }
}