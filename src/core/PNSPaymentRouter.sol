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
     * @param node PNS node hash
     * @param amount Amount of ETH sent
     */
    event ETHTransferToPNS(
        address indexed sender, 
        bytes32 indexed node, 
        uint256 amount
    );
    
    /**
     * @notice Emitted when ERC20 tokens are transferred to a PNS name
     * @param sender Address that sent the tokens
     * @param node PNS node hash
     * @param token ERC20 token address
     * @param amount Amount of tokens sent
     */
    event ERC20TransferToPNS(
        address indexed sender, 
        bytes32 indexed node, 
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
        emit ETHTransferToPNS(msg.sender, node, msg.value);
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
        emit ERC20TransferToPNS(msg.sender, node, token, amount);
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
     * @notice Calculate the node hash for a PNS name
     * @param name The PNS name
     * @return The node hash
     */
    function getNodeHash(string memory name) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(name))));
    }
    
    /**
     * @notice Resolve a PNS name to its associated address
     * @param name The PNS name
     * @param node Optional pre-calculated node hash (to save gas)
     * @return The resolved address
     */
    function resolvePNSNameToAddress(string memory name, bytes32 node) public view returns (address) {
        // If node hash is not provided, calculate it
        if (node == bytes32(0)) {
            node = getNodeHash(name);
        }
        
        // Get resolver address from PNS registry
        address resolver = pnsRegistry.resolver(node);
        if (resolver == address(0)) revert PNSPaymentRouter__ResolverNotSet();
        
        // Get address from resolver
        address addr = IPublicResolver(resolver).addr(node);
        if (addr == address(0)) revert PNSPaymentRouter__AddressNotSetInResolver();
        
        return addr;
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
}
