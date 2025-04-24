// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract NFTRegistrar is ERC721URIStorage, Ownable {
    constructor() ERC721("Domain NFT", "DOMAIN") Ownable(msg.sender) {}
    
    function mint(address to, uint256 tokenId, string memory tokenURI) external onlyOwner returns (bool) {
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        return true;
    }
    
    function burn(uint256 tokenId) external onlyOwner returns (bool) {
        _burn(tokenId);
        return true;
    }
}