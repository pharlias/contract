// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "../interfaces/IPharlias.sol";
import "../structs/PharliaStructs.sol";

/**
 * @title NFTRegistrar
 * @dev NFT contract for domain ownership with improved permission handling and safety checks
 */
contract NFTRegistrar is ERC721URIStorage, Ownable {
    // Custom errors for better gas efficiency and user feedback
    error NFTRegistrar__InvalidRecipient();
    error NFTRegistrar__TokenDoesNotExist(uint256 tokenId);
    error NFTRegistrar__NotTokenOwner(
        uint256 tokenId,
        address sender,
        address owner
    );
    error NFTRegistrar__MintFailed();
    error NFTRegistrar__BurnFailed();
    error NFTRegistrar__EmptyTokenURI();
    error NFTRegistrar__EmptyDomainName();
    error NFTRegistrar__DomainNameNotFound(uint256 tokenId);
    error NFTRegistrar__InvalidPharliasAddress();

    // Events for better tracking and indexing
    // Note: String parameters are intentionally not indexed to allow full value access
    event TokenMinted(
        address indexed to,
        uint256 indexed tokenId,
        string tokenURI,
        string domainName
    );
    event TokenBurned(uint256 indexed tokenId, address indexed previousOwner, string domainName);
    event DomainNameRegistered(uint256 indexed tokenId, string domainName);
    
    // Mapping from token ID to original domain name
    mapping(uint256 => string) private _domainNames;
    
    // Pharlias points system contract reference
    IPharlias public pharlias;
    
    // Flag to enable/disable points calculation
    bool public pointsEnabled;

    constructor() ERC721("Domain NFT", "DOMAIN") Ownable(msg.sender) {
        // Points system is disabled by default until setPharlias is called
        pointsEnabled = false;
    }
    
    /**
     * @notice Set the Pharlias points system contract address
     * @param _pharlias Address of the Pharlias contract
     * @param _enabled Whether to enable points calculation
     * @dev Only contract owner can call this function
     */
    function setPharlias(IPharlias _pharlias, bool _enabled) external onlyOwner {
        if (address(_pharlias) == address(0)) {
            revert NFTRegistrar__InvalidPharliasAddress();
        }
        
        pharlias = _pharlias;
        pointsEnabled = _enabled;
    }

    /**
     * @dev Mints a new token for a domain.
     * @param to The address that will own the minted token
     * @param tokenId The token ID (derived from domain name hash)
     * @param tokenURI_ The token URI for metadata
     * @return success Boolean indicating success
     */
    function mint(
        address to,
        uint256 tokenId,
        string memory tokenURI_,
        string memory domainName
    ) external onlyOwner returns (bool success) {
        // Input validation
        if (to == address(0)) revert NFTRegistrar__InvalidRecipient();
        if (bytes(tokenURI_).length == 0) revert NFTRegistrar__EmptyTokenURI();
        if (bytes(domainName).length == 0) revert NFTRegistrar__EmptyDomainName();

        // Check if token already exists
        try this.ownerOf(tokenId) returns (address) {
            revert NFTRegistrar__MintFailed();
        } catch {
            // Token doesn't exist yet, continue with minting
            _mint(to, tokenId);
            _setTokenURI(tokenId, tokenURI_);
            
            // Store the original domain name
            _domainNames[tokenId] = domainName;
            
            emit DomainNameRegistered(tokenId, domainName);
            emit TokenMinted(to, tokenId, tokenURI_, domainName);
            
            // Award points for PNS creation if points system is enabled
            if (pointsEnabled && address(pharlias) != address(0)) {
                try pharlias.awardPoints(to, PharliaStructs.ACTIVITY_PNS_CREATION) {
                    // Points awarded successfully
                } catch {
                    // Points award failed, but minting succeeded
                    // We don't revert as the main minting process should still succeed
                }
            }
            
            return true;
        }
    }

    /**
     * @dev Burns a token for domain transfer or expiration.
     * @param tokenId The token ID to burn
     * @return success Boolean indicating success
     */
    function burn(uint256 tokenId) external onlyOwner returns (bool success) {
        // Verify token exists before burning
        try this.ownerOf(tokenId) returns (address currentOwner) {
            // Store owner and domain name for event emission
            address previousOwner = currentOwner;
            string memory domainName = _domainNames[tokenId];
            
            // Burn the token
            _burn(tokenId);
            
            // Clear the domain name mapping
            delete _domainNames[tokenId];
            
            emit TokenBurned(tokenId, previousOwner, domainName);
            
            // Award points for token burn/transfer if points system is enabled
            if (pointsEnabled && address(pharlias) != address(0)) {
                try pharlias.awardPoints(previousOwner, PharliaStructs.ACTIVITY_TRANSFER) {
                    // Points awarded successfully
                } catch {
                    // Points award failed, but burning succeeded
                    // We don't revert as the main burning process should still succeed
                }
            }
            
            return true;
        } catch {
            revert NFTRegistrar__TokenDoesNotExist(tokenId);
        }
    }

    /**
     * @dev Overrides the supportsInterface function to maintain compatibility.
     * @param interfaceId The interface identifier
     * @return Boolean indicating whether the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns the original domain name associated with a token ID
     * @param tokenId The token ID to query
     * @return The original domain name string
     */
    function getDomainName(uint256 tokenId) external view returns (string memory) {
        // Verify token exists
        try this.ownerOf(tokenId) returns (address) {
            // Check if domain name exists
            if (bytes(_domainNames[tokenId]).length == 0) {
                revert NFTRegistrar__DomainNameNotFound(tokenId);
            }
            return _domainNames[tokenId];
        } catch {
            revert NFTRegistrar__TokenDoesNotExist(tokenId);
        }
    }
}

