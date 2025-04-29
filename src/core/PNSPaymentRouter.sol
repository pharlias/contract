// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../interfaces/IPNSRegistry.sol";
import "../interfaces/IPublicResolver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PNSPaymentRouter
 * @dev Contract for routing ETH and ERC20 token payments to recipients, including PNS-resolved addresses
 * @notice This contract allows users to send payments to PNS names and addresses with fee management
 */
contract PNSPaymentRouter is Ownable, ReentrancyGuard {
    // ================ Custom Errors ================
    error PNSPaymentRouter__InvalidETHAmount();
    error PNSPaymentRouter__ResolverNotSet();
    error PNSPaymentRouter__AddressNotSetInResolver();
    error PNSPaymentRouter__InvalidName();
    error PNSPaymentRouter__ETHTransferFailed();
    error PNSPaymentRouter__ERC20TransferFailed();
    error PNSPaymentRouter__Unauthorized();
    error PNSPaymentRouter__ZeroAddress();
    error PNSPaymentRouter__InvalidFeePercentage();
    error PNSPaymentRouter__UnsupportedToken(address token);
    error PNSPaymentRouter__ContractPaused();
    error PNSPaymentRouter__BatchArrayMismatch();
    error PNSPaymentRouter__NoFundsToWithdraw();
    error PNSPaymentRouter__TransferFailed();

    // ================ State Variables ================
    /// @notice PNS Registry contract reference
    IPNSRegistry public immutable pnsRegistry;
    
    /// @notice Address that collects fees from transfers
    address public feeCollector;
    
    /// @notice Fee percentage in basis points (1/100 of a percent, 100 = 1%)
    uint256 public feePercentage;
    
    /// @notice Maximum fee percentage allowed (10%)
    uint256 public constant MAX_FEE_PERCENTAGE = 1000;
    
    /// @notice Mapping of user address to interaction count
    mapping(address => uint256) public interactionCount;
    
    /// @notice Mapping of token address to support status
    mapping(address => bool) public supportedTokens;
    
    /// @notice Contract pause state
    bool public paused;

    // ================ Events ================
    /**
     * @notice Emitted when ETH is transferred to a PNS name
     * @param sender Address that sent the ETH
     * @param name PNS name
     * @param amount Amount of ETH sent
     */
    event ETHTransferToPNS(
        address indexed sender, 
        address indexed recipient,
        string name, 
        uint256 amount
    );
    
    /**
     * @notice Emitted when ERC20 tokens are transferred to a PNS name
     * @param sender Address that sent the tokens
     * @param name PNS name
     * @param token ERC20 token address
     * @param amount Amount of tokens sent
     */
    event ERC20TransferToPNS(
        address indexed sender, 
        address indexed recipient,
        string name, 
        address indexed token, 
        uint256 amount
    );
    
    /**
     * @notice Emitted when ETH payment is sent directly to an address
     * @param sender Address that sent the ETH
     * @param recipient Recipient address
     * @param amount Amount of ETH sent
     * @param fee Fee amount collected
     */
    event ETHPaymentSent(
        address indexed sender, 
        address indexed recipient, 
        uint256 amount, 
        uint256 fee
    );
    
    /**
     * @notice Emitted when ERC20 tokens are sent directly to an address
     * @param sender Address that sent the tokens
     * @param recipient Recipient address
     * @param token ERC20 token address
     * @param amount Amount of tokens sent
     * @param fee Fee amount collected
     */
    event ERC20PaymentSent(
        address indexed sender, 
        address indexed recipient, 
        address indexed token, 
        uint256 amount, 
        uint256 fee
    );
    
    /**
     * @notice Emitted when batch ERC20 payments are sent
     * @param sender Address that sent the batch payment
     * @param count Number of recipients in the batch
     */
    event BatchPaymentSent(
        address indexed sender, 
        uint256 count
    );
    
    /**
     * @notice Emitted when fee collector address is updated
     * @param previousCollector Previous fee collector address
     * @param newCollector New fee collector address
     */
    event FeeCollectorUpdated(
        address indexed previousCollector, 
        address indexed newCollector
    );
    
    /**
     * @notice Emitted when fee percentage is updated
     * @param previousPercentage Previous fee percentage
     * @param newPercentage New fee percentage
     */
    event FeePercentageUpdated(
        uint256 previousPercentage, 
        uint256 newPercentage
    );
    
    /**
     * @notice Emitted when token support status is updated
     * @param token Token address
     * @param supported Whether the token is supported
     */
    event TokenSupportUpdated(
        address indexed token, 
        bool supported
    );
    
    /**
     * @notice Emitted when contract pause state is updated
     * @param pauseState New pause state
     */
    event PauseStateUpdated(
        bool pauseState
    );
    
    /**
     * @notice Emitted when funds are withdrawn
     * @param recipient Address receiving the funds
     * @param amount Amount withdrawn
     */
    event FundsWithdrawn(
        address indexed recipient, 
        uint256 amount
    );

    // ================ Modifiers ================
    /**
     * @notice Ensures the contract is not paused
     */
    modifier whenNotPaused() {
        if (paused) revert PNSPaymentRouter__ContractPaused();
        _;
    }

    // ================ Constructor ================
    /**
     * @notice Contract constructor
     * @param _pnsRegistry Address of the PNS Registry contract
     */
    constructor(address _pnsRegistry) Ownable(msg.sender) {
        if (_pnsRegistry == address(0)) revert PNSPaymentRouter__ZeroAddress();
        
        pnsRegistry = IPNSRegistry(_pnsRegistry);
        feeCollector = msg.sender;
        feePercentage = 0; // No fee by default
    }

    // ================ Receive & Fallback ================
    /**
     * @notice Allows the contract to receive ETH
     */
    receive() external payable {}
    
    /**
     * @notice Fallback function that accepts ETH
     */
    fallback() external payable {}

    // ================ External Functions ================
    /**
     * @notice Transfer ETH to an address associated with a PNS name
     * @param name The PNS name
     */
    function transferETHToPNS(string calldata name) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
    {
        // Validate inputs
        if (bytes(name).length == 0) revert PNSPaymentRouter__InvalidName();
        if (msg.value == 0) revert PNSPaymentRouter__InvalidETHAmount();
        
        // Get node hash
        bytes32 node = getNodeHash(name);
        
        // Resolve PNS name to address
        address recipient = resolvePNSNameToAddress(name, node);
        
        // Calculate fee
        uint256 fee = calculateFee(msg.value);
        uint256 transferAmount = msg.value - fee;
        
        // Transfer ETH to recipient
        (bool success, ) = recipient.call{value: transferAmount}("");
        if (!success) revert PNSPaymentRouter__ETHTransferFailed();
        
        // Transfer fee to fee collector if applicable
        if (fee > 0 && feeCollector != address(0)) {
            (bool feeSuccess, ) = feeCollector.call{value: fee}("");
            if (!feeSuccess) {
                // If fee transfer fails, send it to the recipient instead
                (bool recoverySuccess, ) = recipient.call{value: fee}("");
                if (!recoverySuccess) revert PNSPaymentRouter__ETHTransferFailed();
            }
        }
        
        // Increment interaction count
        interactionCount[msg.sender]++;
        
        // Emit event
        emit ETHTransferToPNS(msg.sender, recipient, name, msg.value);
    }
    
    /**
     * @notice Transfer ERC20 tokens to an address associated with a PNS name
     * @param name The PNS name
     * @param token The ERC20 token address
     * @param amount The amount of tokens to transfer
     */
    function transferERC20ToPNS(
        string calldata name, 
        address token, 
        uint256 amount
    ) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        // Validate inputs
        if (bytes(name).length == 0) revert PNSPaymentRouter__InvalidName();
        if (amount == 0) revert PNSPaymentRouter__InvalidETHAmount();
        
        // Check if token is supported (if allowlist is enabled)
        if (supportedTokens[address(0)] && !supportedTokens[token]) {
            revert PNSPaymentRouter__UnsupportedToken(token);
        }
        
        // Get node hash
        bytes32 node = getNodeHash(name);
        
        // Resolve PNS name to address
        address recipient = resolvePNSNameToAddress(name, node);
        
        // Calculate fee
        uint256 fee = calculateFee(amount);
        uint256 transferAmount = amount - fee;
        
        // Transfer tokens to recipient
        IERC20 tokenContract = IERC20(token);
        bool success = tokenContract.transferFrom(msg.sender, recipient, transferAmount);
        if (!success) revert PNSPaymentRouter__ERC20TransferFailed();
        
        // Transfer fee to fee collector if applicable
        if (fee > 0 && feeCollector != address(0)) {
            bool feeSuccess = tokenContract.transferFrom(msg.sender, feeCollector, fee);
            if (!feeSuccess) {
                // If fee transfer fails, attempt to send it to the recipient
                bool recoverySuccess = tokenContract.transferFrom(msg.sender, recipient, fee);
                if (!recoverySuccess) revert PNSPaymentRouter__ERC20TransferFailed();
            }
        }
        
        // Increment interaction count
        interactionCount[msg.sender]++;
        
        // Emit event
        emit ERC20TransferToPNS(msg.sender, recipient, name, token, amount);
    }
    
    /**
     * @notice Send ETH directly to a recipient address
     * @param recipient The recipient address
     */
    function payWithETH(address recipient) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
    {
        // Validate inputs
        if (recipient == address(0)) revert PNSPaymentRouter__ZeroAddress();
        if (msg.value == 0) revert PNSPaymentRouter__InvalidETHAmount();
        
        // Calculate fee
        uint256 fee = calculateFee(msg.value);
        uint256 transferAmount = msg.value - fee;
        
        // Transfer ETH to recipient
        (bool success, ) = recipient.call{value: transferAmount}("");
        if (!success) revert PNSPaymentRouter__ETHTransferFailed();
        
        // Transfer fee to fee collector if applicable
        if (fee > 0 && feeCollector != address(0)) {
            (bool feeSuccess, ) = feeCollector.call{value: fee}("");
            if (!feeSuccess) {
                // If fee transfer fails, send it to the recipient instead
                (bool recoverySuccess, ) = recipient.call{value: fee}("");
                if (!recoverySuccess) revert PNSPaymentRouter__ETHTransferFailed();
            }
        }
        
        // Increment interaction count
        interactionCount[msg.sender]++;
        
        // Emit event
        emit ETHPaymentSent(msg.sender, recipient, transferAmount, fee);
    }
    
    /**
     * @notice Send ERC20 tokens directly to a recipient address
     * @param token The ERC20 token address
     * @param recipient The recipient address
     * @param amount The amount of tokens to transfer
     */
    function payWithERC20(
        address token, 
        address recipient, 
        uint256 amount
    ) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        // Validate inputs
        if (token == address(0) || recipient == address(0)) revert PNSPaymentRouter__ZeroAddress();
        if (amount == 0) revert PNSPaymentRouter__InvalidETHAmount();
        
        // Check if token is supported (if allowlist is enabled)
        if (supportedTokens[address(0)] && !supportedTokens[token]) {
            revert PNSPaymentRouter__UnsupportedToken(token);
        }
        
        // Calculate fee
        uint256 fee = calculateFee(amount);
        uint256 transferAmount = amount - fee;
        
        // Transfer tokens to recipient
        IERC20 tokenContract = IERC20(token);
        bool success = tokenContract.transferFrom(msg.sender, recipient, transferAmount);
        if (!success) revert PNSPaymentRouter__ERC20TransferFailed();
        
        // Transfer fee to fee collector if applicable
        if (fee > 0 && feeCollector != address(0)) {
            bool feeSuccess = tokenContract.transferFrom(msg.sender, feeCollector, fee);
            if (!feeSuccess) {
                // If fee transfer fails, attempt to send it to the recipient
                bool recoverySuccess = tokenContract.transferFrom(msg.sender, recipient, fee);
                if (!recoverySuccess) revert PNSPaymentRouter__ERC20TransferFailed();
            }
        }
        
        // Increment interaction count
        interactionCount[msg.sender]++;
        
        // Emit event
        emit ERC20PaymentSent(msg.sender, recipient, token, transferAmount, fee);
    }
    
    /**
     * @notice Send ERC20 tokens to multiple recipients in one transaction
     * @param tokens Array of ERC20 token addresses
     * @param recipients Array of recipient addresses
     * @param amounts Array of token amounts
     */
    function batchPayWithERC20(
        address[] calldata tokens, 
        address[] calldata recipients, 
        uint256[] calldata amounts
    ) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        // Validate array lengths match
        uint256 count = tokens.length;
        if (count == 0 || recipients.length != count || amounts.length != count) {
            revert PNSPaymentRouter__BatchArrayMismatch();
        }
        
        // Process each payment
        for (uint256 i = 0; i < count; i++) {
            address token = tokens[i];
            address recipient = recipients[i];
            uint256 amount = amounts[i];
            
            // Validate inputs
            if (token == address(0) || recipient == address(0)) revert PNSPaymentRouter__ZeroAddress();
            if (amount == 0) revert PNSPaymentRouter__InvalidETHAmount();
            
            // Check if token is supported (if allowlist is enabled)
            if (supportedTokens[address(0)] && !supportedTokens[token]) {
                revert PNSPaymentRouter__UnsupportedToken(token);
            }
            
            // Calculate fee
            uint256 fee = calculateFee(amount);
            uint256 transferAmount = amount - fee;
            
            // Transfer tokens to recipient
            IERC20 tokenContract = IERC20(token);
            bool success = tokenContract.transferFrom(msg.sender, recipient, transferAmount);
            if (!success) revert PNSPaymentRouter__ERC20TransferFailed();
            
            // Transfer fee to fee collector if applicable
            if (fee > 0 && feeCollector != address(0)) {
                bool feeSuccess = tokenContract.transferFrom(msg.sender, feeCollector, fee);
                if (!feeSuccess) {
                    // If fee transfer fails, attempt to send it to the recipient
                    bool recoverySuccess = tokenContract.transferFrom(msg.sender, recipient, fee);
                    if (!recoverySuccess) revert PNSPaymentRouter__ERC20TransferFailed();
                }
            }
            
            emit ERC20PaymentSent(msg.sender, recipient, token, transferAmount, fee);
        }
        
        // Increment interaction count (only once for batch operation)
        interactionCount[msg.sender]++;
        
        // Emit batch event
        emit BatchPaymentSent(msg.sender, count);
    }

    // ================ Admin Functions ================
    /**
     * @notice Set the fee collector address
     * @param newFeeCollector New fee collector address
     */
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) revert PNSPaymentRouter__ZeroAddress();
        
        address previousCollector = feeCollector;
        feeCollector = newFeeCollector;
        
        emit FeeCollectorUpdated(previousCollector, newFeeCollector);
    }
    
    /**
     * @notice Set the fee percentage (in basis points)
     * @param newFeePercentage New fee percentage (100 = 1%)
     */
    function setFeePercentage(uint256 newFeePercentage) external onlyOwner {
        if (newFeePercentage > MAX_FEE_PERCENTAGE) revert PNSPaymentRouter__InvalidFeePercentage();
        
        uint256 previousPercentage = feePercentage;
        feePercentage = newFeePercentage;
        
        emit FeePercentageUpdated(previousPercentage, newFeePercentage);
    }
    
    /**
     * @notice Set support status for a token
     * @param token Token address
     * @param supported Whether the token is supported
     */
    function setSupportedToken(address token, bool supported) external onlyOwner {
        if (token == address(0)) revert PNSPaymentRouter__ZeroAddress();
        
        supportedTokens[token] = supported;
        
        emit TokenSupportUpdated(token, supported);
    }
    
    /**
     * @notice Set support for all tokens by setting address(0) in the mapping
     * @param supported Whether all tokens are supported
     */
    function setAllTokensSupport(bool supported) external onlyOwner {
        supportedTokens[address(0)] = supported;
        
        emit TokenSupportUpdated(address(0), supported);
    }
    
    /**
     * @notice Set the contract pause state
     * @param newPausedState New pause state
     */
    function setPaused(bool newPausedState) external onlyOwner {
        paused = newPausedState;
        
        emit PauseStateUpdated(newPausedState);
    }
    
    /**
     * @notice Withdraw ETH from the contract
     */
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert PNSPaymentRouter__NoFundsToWithdraw();
        
        address owner = owner();
        (bool success, ) = owner.call{value: balance}("");
        if (!success) revert PNSPaymentRouter__TransferFailed();
        
        emit FundsWithdrawn(owner, balance);
    }
    
    /**
     * @notice Withdraw ERC20 tokens from the contract
     * @param token Token address
     */
    function withdrawERC20(address token) external onlyOwner {
        if (token == address(0)) revert PNSPaymentRouter__ZeroAddress();
        
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        
        if (balance == 0) revert PNSPaymentRouter__NoFundsToWithdraw();
        
        address owner = owner();
        bool success = tokenContract.transfer(owner, balance);
        if (!success) revert PNSPaymentRouter__TransferFailed();
        
        emit FundsWithdrawn(owner, balance);
    }

    // ================ Helper Functions ================
    /**
     * @notice Calculate fee amount based on the transaction amount
     * @param amount The transaction amount
     * @return fee The calculated fee amount
     */
    function calculateFee(uint256 amount) public view returns (uint256) {
        if (feePercentage == 0 || feeCollector == address(0)) {
            return 0;
        }
        
        return (amount * feePercentage) / 10000; // Convert basis points to percentage
    }
    
    /**
     * @notice Calculate the node hash for a PNS name using the namehash algorithm
     * @param name The PNS name
     * @return The node hash
     * @dev Implements the namehash algorithm as specified in EIP-137
     * The algorithm recursively hashes components of the name, starting from the right
     */
    function getNodeHash(string calldata name) public pure returns (bytes32) {
        bytes32 node = 0;
        
        // Handle empty name case early to save gas
        bytes calldata nameParts = bytes(name);
        if (nameParts.length == 0) {
            return node;
        }

        // Validate characters with optimized range checks
        for (uint i = 0; i < nameParts.length; i++) {
            bytes1 char = nameParts[i];
            // Optimized character validation - combined checks to reduce gas
            bool validChar = (
                // Alphanumeric: 0-9, A-Z, a-z
                (char >= 0x30 && char <= 0x39) || 
                (char >= 0x41 && char <= 0x5A) || 
                (char >= 0x61 && char <= 0x7A) || 
                // Special characters: hyphen and dot
                char == 0x2D || char == 0x2E
            );
            if (!validChar) revert PNSPaymentRouter__InvalidName();
        }

        // Process labels from right to left with efficient string slicing
        int length = int(nameParts.length);
        uint lastDot = uint(length);
        
        // Single pass through the string
        for (int i = length - 1; i >= 0; i--) {
            uint currentPos = uint(i);
            
            if (nameParts[currentPos] == '.') {
                // Skip empty labels (consecutive dots)
                if (lastDot == currentPos + 1) {
                    lastDot = currentPos;
                    continue;
                }
                
                // Use direct string slicing for label extraction
                bytes32 labelHash = keccak256(abi.encodePacked(
                    nameParts[currentPos + 1:lastDot]
                ));
                
                // Apply namehash algorithm: node = keccak256(node + keccak256(label))
                node = keccak256(abi.encodePacked(node, labelHash));
                lastDot = currentPos;
            } else if (i == 0) {
                // Handle the leftmost label efficiently with string slicing
                bytes32 labelHash = keccak256(abi.encodePacked(
                    nameParts[0:lastDot]
                ));
                
                // Apply namehash algorithm for the final label
                node = keccak256(abi.encodePacked(node, labelHash));
            }
        }
        
        return node;
    }
    
    /**
     * @notice Resolve a PNS name to its associated address
     * @param name The PNS name
     * @param node Optional pre-calculated node hash (to save gas)
     * @return The resolved address using the following resolution strategy:
     * 1. If resolver is set and has an address, use that address
     * 2. Otherwise, fall back to the node owner's address
     * @dev This implementation follows a fallback pattern where the owner address
     *      is used when either the resolver is not set or the resolver has no address
     */
    function resolvePNSNameToAddress(string calldata name, bytes32 node) public view returns (address) {
        // If node hash is not provided, calculate it
        if (node == bytes32(0)) {
            node = getNodeHash(name);
        }
        
        // First, try to get the owner of the node
        address owner = pnsRegistry.owner(node);
        if (owner == address(0)) {
            revert PNSPaymentRouter__InvalidName();
        }
        
        // Get resolver address from PNS registry
        address resolver = pnsRegistry.resolver(node);
        if (resolver != address(0)) {
            // Try to get address from resolver
            address addr = IPublicResolver(resolver).addr(node);
            if (addr != address(0)) {
                return addr;
            }
        }
        
        // Fall back to owner if no valid resolver address is found
        return owner;
    }
    
    /**
     * @notice Check if a token is supported for payments
     * @param token Token address to check
     * @return Whether the token is supported
     */
    function isTokenSupported(address token) public view returns (bool) {
        // If allowlist is disabled (address(0) is false), all tokens are supported
        if (!supportedTokens[address(0)]) {
            return true;
        }
        
        // Otherwise, check if the specific token is supported
        return supportedTokens[token];
    }

    /**
     * @notice Debug function to trace PNS name resolution process
     * @param name The PNS name to resolve
     * @return nodeHash The calculated node hash
     * @return ownerAddress The owner address from registry
     * @return resolverAddress The resolver address
     * @return resolverResult The address from resolver (if available)
     * @return finalAddress The final resolved address 
     * @dev This function exposes each step of the resolution process for debugging
     */
    function debugPNSResolution(string calldata name) public view returns (
        bytes32 nodeHash,
        address ownerAddress,
        address resolverAddress,
        address resolverResult,
        address finalAddress
    ) {
        // Step 1: Calculate node hash
        nodeHash = getNodeHash(name);
        
        // Step 2: Get owner from registry
        try pnsRegistry.owner(nodeHash) returns (address owner) {
            ownerAddress = owner;
            
            // Step 3: Get resolver address
            try pnsRegistry.resolver(nodeHash) returns (address resolver) {
                resolverAddress = resolver;
                
                // Step 4: If resolver exists, try to get address from it
                if (resolver != address(0)) {
                    try IPublicResolver(resolver).addr(nodeHash) returns (address addr) {
                        resolverResult = addr;
                        
                        // If resolver returns a valid address, use it
                        if (addr != address(0)) {
                            finalAddress = addr;
                        } else {
                            // Otherwise fallback to owner
                            finalAddress = owner;
                        }
                    } catch {
                        // Error calling resolver, fallback to owner
                        resolverResult = address(0);
                        finalAddress = owner;
                    }
                } else {
                    // No resolver, use owner
                    resolverResult = address(0);
                    finalAddress = owner;
                }
            } catch {
                // Failed to get resolver, use owner
                resolverAddress = address(0);
                resolverResult = address(0);
                finalAddress = owner;
            }
        } catch {
            // Failed to get owner
            ownerAddress = address(0);
            resolverAddress = address(0);
            resolverResult = address(0);
            finalAddress = address(0);
        }
        
        return (nodeHash, ownerAddress, resolverAddress, resolverResult, finalAddress);
    }
}
