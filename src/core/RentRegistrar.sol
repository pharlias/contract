// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./NFTRegistrar.sol";
import "./PNSRegistry.sol";
import "../structs/RentRegistrarStructs.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title RentRegistrar
 * @dev Contract for managing domain registration, renewal, and transfers with ENS integration
 * @notice This contract allows users to register, renew, and transfer domain names
 */
contract RentRegistrar is Ownable {
    // ================ Custom Errors ================
    error RentRegistrar__InvalidRegistryAddress();
    error RentRegistrar__InvalidNFTRegistrarAddress();
    error RentRegistrar__InvalidRootNode();
    error RentRegistrar__InvalidNewOwner();
    error RentRegistrar__InsufficientDuration(
        uint256 provided,
        uint256 minimum
    );
    error RentRegistrar__DomainNotAvailable(string name);
    error RentRegistrar__InsufficientPayment(
        uint256 required,
        uint256 provided
    );
    error RentRegistrar__DomainNotRegistered(string name);
    error RentRegistrar__NotDomainOwner(
        string name,
        address caller,
        address owner
    );
    error RentRegistrar__NoFundsToWithdraw();
    error RentRegistrar__TransferFailed();
    error RentRegistrar__NFTMintFailed(uint256 tokenId);
    error RentRegistrar__NFTBurnFailed(uint256 tokenId);
    error RentRegistrar__NFTTransferFailed(uint256 tokenId);
    error RentRegistrar__DomainExpired(string name, uint256 expiry);
    error RentRegistrar__ENSUpdateFailed(bytes32 node);
    error RentRegistrar__InvalidENSNode();
    error RentRegistrar__InvalidPriceAmount();
    error NameMustBeAtLeastThreeCharacter(
        string name,
        uint256 length
    );

    // ================ State Variables ================
    /// @notice ENS registry contract reference
    PNSRegistry public ens;

    /// @notice NFT token contract reference
    NFTRegistrar public nft;

    /// @notice Root node for domain names in the ENS registry
    bytes32 public rootNode;

    /// @notice Yearly rent prices for domain registration based on length
    uint256 public priceForThreeChar;       // Price for 3-character domains
    uint256 public priceForFourToFiveChar;  // Price for 4-5 character domains
    uint256 public priceForSixToNineChar;   // Price for 6-9 character domains
    uint256 public priceForTenPlusChar;     // Price for 10+ character domains

    // ================ Events ================
    /**
     * @notice Emitted when a domain is registered
     * @param name Domain name (not indexed to allow full value access)
     * @param owner Owner address
     * @param expires Expiration timestamp
     * @param tokenId NFT token ID
     */
    event DomainRegistered(
        string name,
        address indexed owner,
        uint256 expires,
        uint256 tokenId
    );

    /**
     * @notice Emitted when a domain is renewed
     * @param name Domain name (not indexed to allow full value access)
     * @param owner Owner address
     * @param newExpiry New expiration timestamp
     */
    event DomainRenewed(
        string name,
        address indexed owner,
        uint256 newExpiry
    );

    /**
     * @notice Emitted when a domain ownership is transferred
     * @param name Domain name (not indexed to allow full value access)
     * @param from Previous owner
     * @param to New owner
     * @param tokenId NFT token ID
     */
    event DomainTransferred(
        string name,
        address indexed from,
        address indexed to,
        uint256 tokenId
    );

    /**
     * @notice Emitted when funds are withdrawn by contract owner
     * @param owner Contract owner address
     * @param amount Amount withdrawn
     */
    event FundsWithdrawn(address indexed owner, uint256 amount);

    /**
     * @notice Emitted when ENS records are updated
     * @param node ENS node hash
     * @param owner New owner address
     */
    event ENSRecordUpdated(bytes32 indexed node, address indexed owner);

    /**
     * @notice Emitted when rent prices are updated
     * @param updater Address that updated the prices
     */
    event RentPricesUpdated(address indexed updater);

    // ================ Storage ================
    /// @dev Mapping from domain name (plain text) to Domain struct
    mapping(string => RentRegistrarStructs.Domain) public domains;

    // ================ Constructor ================
    /**
     * @notice Contract constructor
     * @param _ens Address of the ENS registry contract
     * @param _nft Address of the NFT registry contract
     * @param _rootNode Root node for domain names
     */
    constructor(
        PNSRegistry _ens,
        NFTRegistrar _nft,
        bytes32 _rootNode
    ) Ownable(msg.sender) {
        if (address(_ens) == address(0)) {
            revert RentRegistrar__InvalidRegistryAddress();
        }
        if (address(_nft) == address(0)) {
            revert RentRegistrar__InvalidNFTRegistrarAddress();
        }
        if (_rootNode == bytes32(0)) {
            revert RentRegistrar__InvalidRootNode();
        }

        ens = _ens;
        nft = _nft;
        rootNode = _rootNode;

        // Verify ownership of root node - contract must be able to control root node
        address rootOwner = _ens.owner(_rootNode);
        if (rootOwner != address(this) && rootOwner != msg.sender) {
            revert RentRegistrar__InvalidRootNode();
        }

        // Initialize default prices
        priceForThreeChar = 0.1 ether;
        priceForFourToFiveChar = 0.01 ether;
        priceForSixToNineChar = 0.001 ether;
        priceForTenPlusChar = 0.0001 ether;
    }

    // ================ External Functions ================
    /**
     * @notice Calculate the rent price for a given duration
     * @param numYears Number of years for domain registration
     * @param name Domain name to calculate price for
     * @return Price in wei
     */
    function rentPrice(uint256 numYears, string memory name) public view returns (uint256) {
        uint256 len = _stringLength(name);
        require(len >= 3, "Make it loooong!");

        uint256 pricePerYear;
        if (len == 3) {
            pricePerYear = priceForThreeChar;
        } else if (len >= 4 && len <= 5) {
            pricePerYear = priceForFourToFiveChar;
        } else if (len >= 6 && len <= 9) {
            pricePerYear = priceForSixToNineChar;
        } else {
            pricePerYear = priceForTenPlusChar;
        }

        return pricePerYear * numYears;
    }

    /**
     * @notice Update rent prices for domains
     * @param _priceForThreeChar Price for 3-character domains (in wei)
     * @param _priceForFourToFiveChar Price for 4-5 character domains (in wei)
     * @param _priceForSixToNineChar Price for 6-9 character domains (in wei)
     * @param _priceForTenPlusChar Price for 10+ character domains (in wei)
     * @dev Only contract owner can call this function
     */
    function updateRentPrice(
        uint256 _priceForThreeChar,
        uint256 _priceForFourToFiveChar,
        uint256 _priceForSixToNineChar,
        uint256 _priceForTenPlusChar
    ) external onlyOwner {
        // Validate prices are reasonable (non-zero)
        if (_priceForThreeChar == 0 || 
            _priceForFourToFiveChar == 0 || 
            _priceForSixToNineChar == 0 || 
            _priceForTenPlusChar == 0) {
            revert RentRegistrar__InvalidPriceAmount();
        }

        // Update price state variables
        priceForThreeChar = _priceForThreeChar;
        priceForFourToFiveChar = _priceForFourToFiveChar;
        priceForSixToNineChar = _priceForSixToNineChar;
        priceForTenPlusChar = _priceForTenPlusChar;

        // Emit event to notify price update
        emit RentPricesUpdated(msg.sender);
    }

    /**
     * @notice Calculate string length
     * @param s String to measure
     * @return length in characters (accounting for UTF-8 encoding)
     */
    function _stringLength(string memory s) internal pure returns (uint256) {
        uint256 length = 0;
        uint256 i = 0;
        bytes memory string_rep = bytes(s);

        while (i < string_rep.length) {
            uint8 b = uint8(string_rep[i]);
            // UTF-8 multi-byte character handling
            if (b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
            length++;
        }

        return length;
    }

    /**
     * @notice Check if a domain name is available for registration
     * @param name Domain name to check
     * @return True if domain is available
     */
    function isAvailable(string memory name) public view returns (bool) {
        RentRegistrarStructs.Domain memory domain = domains[name];
        return domain.expires < block.timestamp;
    }

    /**
     * @notice Register a new domain name
     * @param name Domain name to register
     * @param owner Address that will own the domain
     * @param durationInYears Registration duration in years
     * @param tokenURI URI for the NFT metadata
     */
    function register(
        string memory name,
        address owner,
        uint256 durationInYears,
        string memory tokenURI
    ) external payable {
        // Validate inputs
        if (_stringLength(name) < 3) {
            revert NameMustBeAtLeastThreeCharacter(name, _stringLength(name));
        }
        if (durationInYears < 1) {
            revert RentRegistrar__InsufficientDuration(durationInYears, 1);
        }
        if (owner == address(0)) {
            revert RentRegistrar__InvalidNewOwner();
        }

        // Check domain availability
        if (!isAvailable(name)) {
            revert RentRegistrar__DomainNotAvailable(name);
        }

        // Check payment
        uint256 price = rentPrice(durationInYears, name);
        if (msg.value < price) {
            revert RentRegistrar__InsufficientPayment(price, msg.value);
        }

        // Create ENS label and node (only hashing where needed for ENS)
        bytes32 label = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));
        if (node == bytes32(0)) {
            revert RentRegistrar__InvalidENSNode();
        }

        // Calculate expiration
        uint256 expires = block.timestamp + durationInYears * 365 days;

        // Update domain record - now using plain name as key
        domains[name] = RentRegistrarStructs.Domain(owner, expires);

        // Verify control of root node first
        address rootOwner = ens.owner(rootNode);
        if (rootOwner != address(this)) {
            revert RentRegistrar__ENSUpdateFailed(rootNode);
        }

        // Update ENS record - use setSubnodeOwner for proper hierarchy
        try ens.setSubnodeOwner(rootNode, label, owner) {
            emit ENSRecordUpdated(node, owner);
        } catch {
            revert RentRegistrar__ENSUpdateFailed(node);
        }
        uint256 tokenId = uint256(label);

        // Before minting new NFT, try to burn any existing token
        try nft.ownerOf(tokenId) returns (address) {
            // Token exists, burn it first
            bool burnSuccess = nft.burn(tokenId);
            if (!burnSuccess) {
                revert RentRegistrar__NFTBurnFailed(tokenId);
            }
        } catch {
            // Token doesn't exist, which is fine
        }

        // Now mint new NFT
        bool success = nft.mint(owner, tokenId, tokenURI, name);
        if (!success) {
            revert RentRegistrar__NFTMintFailed(tokenId);
        }

        emit DomainRegistered(name, owner, expires, tokenId);
    }

    /**
     * @notice Renew a domain registration
     * @param name Domain name to renew
     * @param additionalYears Number of additional years to add
     */
    function renew(
        string memory name,
        uint256 additionalYears
    ) external payable {
        // Validate inputs
        if (additionalYears < 1) {
            revert RentRegistrar__InsufficientDuration(additionalYears, 1);
        }

        // Use string directly as key in the mapping
        RentRegistrarStructs.Domain storage domain = domains[name];

        // Check domain registration
        if (domain.owner == address(0)) {
            revert RentRegistrar__DomainNotRegistered(name);
        }

        // Check ownership
        if (msg.sender != domain.owner) {
            revert RentRegistrar__NotDomainOwner(
                name,
                msg.sender,
                domain.owner
            );
        }

        // Check payment
        uint256 price = rentPrice(additionalYears, name);
        if (msg.value < price) {
            revert RentRegistrar__InsufficientPayment(price, msg.value);
        }

        // Update expiration date
        if (domain.expires < block.timestamp) {
            // If already expired, start fresh from current time
            domain.expires = block.timestamp + additionalYears * 365 days;
        } else {
            // Otherwise add to existing expiration
            domain.expires += additionalYears * 365 days;
        }

        emit DomainRenewed(name, domain.owner, domain.expires);
    }

    /**
     * @notice Transfer domain ownership to a new address
     * @param name Domain name to transfer
     * @param newOwner New owner address
     */
    function transferOwnership(string memory name, address newOwner) external {
        // Validate inputs
        if (newOwner == address(0)) {
            revert RentRegistrar__InvalidNewOwner();
        }

        // Access domain directly by name
        RentRegistrarStructs.Domain storage domain = domains[name];

        // Check domain registration
        if (domain.owner == address(0)) {
            revert RentRegistrar__DomainNotRegistered(name);
        }

        // Check ownership
        if (msg.sender != domain.owner) {
            revert RentRegistrar__NotDomainOwner(
                name,
                msg.sender,
                domain.owner
            );
        }

        // Check expiration
        if (domain.expires < block.timestamp) {
            revert RentRegistrar__DomainExpired(name, domain.expires);
        }

        // Hash for ENS and NFT purposes only where needed
        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);
        string memory uri = nft.tokenURI(tokenId);

        // Store previous owner for event emission
        address previousOwner = domain.owner;

        // Update domain ownership record
        domain.owner = newOwner;

        // Verify control of root node first
        address rootOwner = ens.owner(rootNode);
        if (rootOwner != address(this)) {
            revert RentRegistrar__ENSUpdateFailed(rootNode);
        }

        // Update ENS registry - use setSubnodeOwner for proper hierarchy
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));
        try ens.setSubnodeOwner(rootNode, label, newOwner) {
            emit ENSRecordUpdated(node, newOwner);
        } catch {
            revert RentRegistrar__ENSUpdateFailed(node);
        }

        // Handle NFT transfer in a safer way
        // First check if the NFT exists
        try nft.ownerOf(tokenId) returns (address /* currentOwner */) {
            // If token exists, burn it
            bool burnSuccess = nft.burn(tokenId);
            if (!burnSuccess) {
                revert RentRegistrar__NFTBurnFailed(tokenId);
            }
        } catch {
            // Token doesn't exist, which is fine - continue
        }

        // Mint new NFT to the new owner
        bool mintSuccess = nft.mint(newOwner, tokenId, uri, name);
        if (!mintSuccess) {
            revert RentRegistrar__NFTMintFailed(tokenId);
        }

        emit DomainTransferred(name, previousOwner, newOwner, tokenId);
    }

    /**
     * @notice Get domain expiration timestamp
     * @param name Domain name to check
     * @return Expiration timestamp
     */
    function domainExpires(string memory name) external view returns (uint256) {
        return domains[name].expires;
    }

    /**
     * @notice Get ENS node for a domain name
     * @param name Domain name
     * @return ENS node hash
     */
    function getNode(string memory name) public view returns (bytes32) {
        bytes32 label = keccak256(bytes(name));
        return keccak256(abi.encodePacked(rootNode, label));
    }

    /**
     * @notice Check if a domain is owned by an address
     * @param name Domain name to check
     * @param owner Address to check
     * @return True if owner matches
     */
    function isDomainOwner(
        string memory name,
        address owner
    ) public view returns (bool) {
        return domains[name].owner == owner;
    }

    /**
     * @notice Withdraw contract funds to owner
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            revert RentRegistrar__NoFundsToWithdraw();
        }

        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) {
            revert RentRegistrar__TransferFailed();
        }

        emit FundsWithdrawn(owner(), balance);
    }
}

