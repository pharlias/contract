// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTRegistrar is ERC721URIStorage, Ownable {
    uint256 public tokenCounter;

    constructor() ERC721("Pharos Name Sevice", "Pharoswho") {}

    function mint(address to, uint256 tokenId, string memory tokenURI) external onlyOwner {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }
}
