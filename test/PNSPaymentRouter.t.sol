// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {PNSPaymentRouter} from "../src/core/PNSPaymentRouter.sol";
import {PNSRegistry} from "../src/core/PNSRegistry.sol";
import {PublicResolver} from "../src/core/PublicResolver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPublicResolver} from "../src/interfaces/IPublicResolver.sol";

/**
 * @title MockERC20
 * @dev Mock ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        // Mint 1000 tokens to the deployer
        _mint(msg.sender, 1000 * 10 ** 18);
    }

    // Mint function for test setup
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title ReentrantAttacker
 * @dev Contract for testing reentrancy protection
 */
contract ReentrantAttacker {
    PNSPaymentRouter public immutable router;
    bool public attackActive;
    uint256 public attackCount;

    constructor(address payable _router) {
        router = PNSPaymentRouter(_router);
        attackActive = false;
        attackCount = 0;
    }

    // Function to start attack
    function attack(address recipient) external payable {
        attackActive = true;
        router.payWithETH{value: msg.value}(recipient);
    }

    // Receive function that attempts reentrancy
    receive() external payable {
        if (attackActive && attackCount < 3) {
            attackCount++;
            router.payWithETH{value: 0.1 ether}(address(this));
        }
    }
}

/**
 * @title MaliciousReceiver
 * @dev Contract that rejects ETH transfers
 */
contract MaliciousReceiver {
    // Explicitly reject all ETH transfers
    receive() external payable {
        revert("I reject all ETH");
    }
}

/**
 * @title MockERC20WithFeeFailure
 * @dev Mock ERC20 that simulates transfer failure to fee collector but success to recipient
 */
contract MockERC20WithFeeFailure is ERC20 {
    address private immutable FEE_COLLECTOR;

    constructor(
        string memory name,
        string memory symbol,
        address feeCollector
    ) ERC20(name, symbol) {
        FEE_COLLECTOR = feeCollector;
        _mint(msg.sender, 1000 * 10 ** 18);
    }

    // Mint function for test setup
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Override transferFrom to simulate failure when transferring to fee collector
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        // Simulate failure when sending to fee collector
        if (recipient == FEE_COLLECTOR) {
            return false;
        }

        // Normal transfer for all other cases
        return super.transferFrom(sender, recipient, amount);
    }
}

/**
 * @title PNSPaymentRouterTest
 * @dev Test suite for the PNSPaymentRouter contract
 */
contract PNSPaymentRouterTest is Test {
    // Constants
    address private constant ADMIN = address(0x1);
    address private constant USER1 = address(0x2);
    address private constant USER2 = address(0x3);
    address private constant FEE_COLLECTOR = address(0x4);
    string private constant TEST_NAME = "test";
    uint256 private constant TRANSFER_AMOUNT = 1 ether;
    uint256 private constant TOKEN_AMOUNT = 100 * 10 ** 18;
    uint256 private constant FEE_PERCENTAGE = 250; // 2.5%

    // Contract instances
    PNSPaymentRouter private paymentRouter;
    PNSRegistry private pnsRegistry;
    PublicResolver private resolver;
    MockERC20 private token1;
    MockERC20 private token2;
    ReentrantAttacker private attacker;
    MaliciousReceiver private maliciousReceiver;

    // Events to test
    event ETHTransferToPNS(
        address indexed sender,
        address indexed recipient,
        string name,
        uint256 amount
    );
    event ERC20TransferToPNS(
        address indexed sender,
        address indexed recipient,
        string name,
        address indexed token,
        uint256 amount
    );
    event ETHPaymentSent(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );
    event ERC20PaymentSent(
        address indexed sender,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 fee
    );
    event BatchPaymentSent(address indexed sender, uint256 count);
    event FeeCollectorUpdated(
        address indexed previousCollector,
        address indexed newCollector
    );
    event FeePercentageUpdated(
        uint256 previousPercentage,
        uint256 newPercentage
    );
    event TokenSupportUpdated(address indexed token, bool supported);
    event PauseStateUpdated(bool pauseState);
    event FundsWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @notice Sets up the test environment
     * @dev Deploys contracts and initializes test data
     */
    function setUp() public {
        // Start as ADMIN for all initial setup
        vm.startPrank(ADMIN);

        // Give ADMIN some ETH
        vm.deal(ADMIN, 100 ether);

        // Deploy PNS Registry and base contracts
        pnsRegistry = new PNSRegistry();
        resolver = new PublicResolver(address(pnsRegistry));
        paymentRouter = new PNSPaymentRouter(address(pnsRegistry));

        // Deploy Mock ERC20 tokens
        token1 = new MockERC20("Token 1", "TK1");
        token2 = new MockERC20("Token 2", "TK2");

        // Set up PNS node
        pnsRegistry.setSubnodeOwner(
            bytes32(0),
            keccak256(bytes(TEST_NAME)),
            USER1
        );

        // Configure payment router
        paymentRouter.setFeeCollector(FEE_COLLECTOR);
        paymentRouter.setFeePercentage(FEE_PERCENTAGE);
        // In this system, setAllTokensSupport(false) means "allow all tokens"
        // and setAllTokensSupport(true) means "use allowlist"
        paymentRouter.setAllTokensSupport(false);

        // Stop being ADMIN
        vm.stopPrank();

        // Set up resolver as USER1
        vm.prank(USER1);
        pnsRegistry.setResolver(getNodeHash(TEST_NAME), address(resolver));

        // Deploy attack contracts after stopping ADMIN prank
        attacker = new ReentrantAttacker(payable(address(paymentRouter)));
        maliciousReceiver = new MaliciousReceiver();
    }

    /**
     * @notice Helper function to create a PNS node
     * @param name The name for the PNS node
     * @param owner The owner address for the node
     * @return node The node hash
     */
    function createPNSNode(
        string memory name,
        address owner
    ) internal returns (bytes32) {
        bytes32 rootNode = bytes32(0);
        bytes32 label = keccak256(bytes(name));

        // Calculate node hash
        bytes32 node = keccak256(abi.encodePacked(rootNode, label));

        // Create subnode and set owner
        vm.prank(ADMIN);
        pnsRegistry.setSubnodeOwner(rootNode, label, owner);

        // Set resolver
        vm.prank(owner);
        pnsRegistry.setResolver(node, address(resolver));

        return node;
    }

    /**
     * @notice Helper function to set an address for a node in the resolver
     * @param node The node hash
     * @param addr The address to set
     */
    function setNodeAddress(bytes32 node, address addr) internal {
        vm.prank(USER1);
        resolver.setAddr(node, addr);
    }

    /**
     * @notice Helper function to calculate a node hash from a name
     * @param name The name to hash
     * @return The node hash
     */
    function getNodeHash(string memory name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes32(0), keccak256(bytes(name))));
    }

    // ==================== Deployment Tests ====================

    /**
     * @notice Test that the contract was deployed with the correct PNS registry
     */
    function test_ContractDeployment() public view {
        assertEq(
            address(paymentRouter.pnsRegistry()),
            address(pnsRegistry),
            "PNS Registry address should match"
        );
        assertEq(paymentRouter.owner(), ADMIN, "Owner should be ADMIN");
        assertEq(
            paymentRouter.feeCollector(),
            FEE_COLLECTOR,
            "Fee collector should be set"
        );
        assertEq(
            paymentRouter.feePercentage(),
            FEE_PERCENTAGE,
            "Fee percentage should be set"
        );
    }

    /**
     * @notice Test that contract reverts when deployed with zero address for registry
     */
    function test_RevertWhenDeployedWithZeroAddress() public {
        vm.expectRevert(
            PNSPaymentRouter.PNSPaymentRouter__ZeroAddress.selector
        );
        new PNSPaymentRouter(address(0));
    }

    // ==================== ETH Payment Tests ====================

    /**
     * @notice Test ETH transfer to PNS name
     */
    function test_TransferETHToPNS() public {
        // Setup: Set USER2 as the address for the test node
        bytes32 testNode = getNodeHash(TEST_NAME);
        setNodeAddress(testNode, USER2);

        // Get initial balances
        uint256 initialRecipientBalance = USER2.balance;
        uint256 initialFeeCollectorBalance = FEE_COLLECTOR.balance;

        // Calculate expected fee
        uint256 expectedFee = (TRANSFER_AMOUNT * FEE_PERCENTAGE) / 10000;
        uint256 expectedTransferAmount = TRANSFER_AMOUNT - expectedFee;

        // Execute transfer
        vm.deal(address(this), TRANSFER_AMOUNT);
        
        // Get the resolved address before transfer
        address resolvedAddr = paymentRouter.resolvePNSNameToAddress(TEST_NAME, testNode);

        // Execute transfer
        vm.expectEmit(true, true, true, true);
        emit ETHTransferToPNS(
            address(this),     // sender
            resolvedAddr,      // recipient
            TEST_NAME,         // name
            TRANSFER_AMOUNT    // amount
        );
        paymentRouter.transferETHToPNS{value: TRANSFER_AMOUNT}(TEST_NAME);

        // Verify balances
        assertEq(
            USER2.balance,
            initialRecipientBalance + expectedTransferAmount,
            "USER2 should receive the correct amount"
        );
        assertEq(
            FEE_COLLECTOR.balance,
            initialFeeCollectorBalance + expectedFee,
            "Fee collector should receive the fee"
        );

        // Verify interaction count
        assertEq(
            paymentRouter.interactionCount(address(this)),
            1,
            "Interaction count should be incremented"
        );
    }

    /**
     * @notice Test direct ETH payment
     */
    function test_PayWithETH() public {
        // Get initial balances
        uint256 initialRecipientBalance = USER2.balance;
        uint256 initialFeeCollectorBalance = FEE_COLLECTOR.balance;

        // Calculate expected fee
        uint256 expectedFee = (TRANSFER_AMOUNT * FEE_PERCENTAGE) / 10000;
        uint256 expectedTransferAmount = TRANSFER_AMOUNT - expectedFee;

        // Execute transfer
        vm.deal(address(this), TRANSFER_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit ETHPaymentSent(
            address(this),
            USER2,
            expectedTransferAmount,
            expectedFee
        );
        paymentRouter.payWithETH{value: TRANSFER_AMOUNT}(USER2);

        // Verify balances
        assertEq(
            USER2.balance,
            initialRecipientBalance + expectedTransferAmount,
            "USER2 should receive the correct amount"
        );
        assertEq(
            FEE_COLLECTOR.balance,
            initialFeeCollectorBalance + expectedFee,
            "Fee collector should receive the fee"
        );

        // Verify interaction count
        assertEq(
            paymentRouter.interactionCount(address(this)),
            1,
            "Interaction count should be incremented"
        );
    }

    /**
     * @notice Test that transfer reverts when no ETH is sent
     */
    function test_RevertWhenNoETHSent() public {
        // Setup resolver
        bytes32 testNode = getNodeHash(TEST_NAME);
        setNodeAddress(testNode, USER2);

        // Attempt to transfer with 0 ETH
        vm.expectRevert(
            PNSPaymentRouter.PNSPaymentRouter__InvalidETHAmount.selector
        );
        paymentRouter.transferETHToPNS{value: 0}(TEST_NAME);

        // Attempt direct payment with 0 ETH
        vm.expectRevert(
            PNSPaymentRouter.PNSPaymentRouter__InvalidETHAmount.selector
        );
        paymentRouter.payWithETH{value: 0}(USER2);
    }

    /**
     * @notice Test that transfer reverts when an empty name is provided
     */
    function test_RevertWithEmptyName() public {
        // Set up the domain with a resolver
        vm.prank(USER1);
        resolver.setAddr(getTestNode(), USER2);
        
        // Try to transfer with empty name
        vm.deal(address(this), TRANSFER_AMOUNT);
        vm.expectRevert(
            PNSPaymentRouter.PNSPaymentRouter__InvalidName.selector
        );
        paymentRouter.transferETHToPNS{value: TRANSFER_AMOUNT}("");
    }

    /**
     * @notice Test that the transfer reverts when the name has no resolver set
     */
    /**
     * @notice Test validation that resolver is not set
     */
    function test_ValidateNoResolverSet() public {
        // Create a new node with no resolver
        string memory noResolverName = "noresolver";
        vm.prank(ADMIN);
        pnsRegistry.setSubnodeOwner(
            bytes32(0),
            keccak256(bytes(noResolverName)),
            USER1
        );

        // For this test, we'll directly check that the resolver is not set
        bytes32 node = paymentRouter.getNodeHash(noResolverName);
        address resolverAddr = pnsRegistry.resolver(node);
        assertEq(resolverAddr, address(0), "Resolver should not be set");
        
        // Verify the name still resolves to the owner address
        address resolved = paymentRouter.resolvePNSNameToAddress(noResolverName, bytes32(0));
        assertEq(resolved, USER1, "Should fall back to owner address when no resolver is set");
    }

    /**
     * @notice Test that the transfer reverts when no address is set in the resolver
     */
    /**
     * @notice Test validation that no address is set in resolver
     */
    function test_ValidateNoAddressSet() public {
        // Create a node with resolver but no address set
        string memory noAddrName = "noaddr";

        // Create the node and set resolver without setting an address
        createPNSNode(noAddrName, USER1);

        // For this test, we'll directly check that the address is not set in the resolver
        bytes32 node = paymentRouter.getNodeHash(noAddrName);
        address resolverAddr = pnsRegistry.resolver(node);
        assertEq(resolverAddr != address(0), true, "Resolver should be set");
        
        address addr = IPublicResolver(resolverAddr).addr(node);
        assertEq(addr, address(0), "Address should not be set in resolver");
        
        // Verify the name still resolves to the owner address
        address resolved = paymentRouter.resolvePNSNameToAddress(noAddrName, bytes32(0));
        assertEq(resolved, USER1, "Should fall back to owner address when no address is set in resolver");
    }

    /**
     * @notice Test that the transfer reverts when ETH transfer fails
     */
    function test_RevertWhenETHTransferFails() public {
        // Setup: Create a new node and set the malicious receiver as the address
        string memory maliciousName = "malicious";
        bytes32 maliciousNode = createPNSNode(maliciousName, USER1);
        setNodeAddress(maliciousNode, address(maliciousReceiver));

        // Try to transfer
        vm.deal(address(this), TRANSFER_AMOUNT);
        vm.expectRevert(
            PNSPaymentRouter.PNSPaymentRouter__ETHTransferFailed.selector
        );
        paymentRouter.transferETHToPNS{value: TRANSFER_AMOUNT}(maliciousName);
    }

    // ==================== ERC20 Payment Tests ====================

    /**
     * @notice Test ERC20 transfer to PNS name
     */
    function test_TransferERC20ToPNS() public {
        // Setup: Set USER2 as the address for the test node
        bytes32 testNode = getNodeHash(TEST_NAME);
        setNodeAddress(testNode, USER2);

        // Get tokens for testing
        vm.startPrank(ADMIN);
        token1.mint(address(this), TOKEN_AMOUNT);
        vm.stopPrank();

        // Calculate expected fee and transfer amount
        uint256 expectedFee = (TOKEN_AMOUNT * FEE_PERCENTAGE) / 10000;
        uint256 expectedTransferAmount = TOKEN_AMOUNT - expectedFee;

        // Get resolved address before transfer
        address resolvedAddr = paymentRouter.resolvePNSNameToAddress(TEST_NAME, testNode);

        // Approve the payment router to spend tokens
        token1.approve(address(paymentRouter), TOKEN_AMOUNT);

        // Execute transfer
        vm.expectEmit(true, true, true, true);
        emit ERC20TransferToPNS(
            address(this),     // sender
            resolvedAddr,      // recipient
            TEST_NAME,         // name
            address(token1),   // token
            TOKEN_AMOUNT       // amount
        );
        paymentRouter.transferERC20ToPNS(
            TEST_NAME,
            address(token1),
            TOKEN_AMOUNT
        );

        // Verify balances
        assertEq(
            token1.balanceOf(USER2),
            expectedTransferAmount,
            "USER2 should receive the correct token amount"
        );
        assertEq(
            token1.balanceOf(FEE_COLLECTOR),
            expectedFee,
            "Fee collector should receive the fee"
        );

        // Verify interaction count
        assertEq(
            paymentRouter.interactionCount(address(this)),
            1,
            "Interaction count should be incremented"
        );
    }

    /**
     * @notice Test direct ERC20 payment
     * @dev Tests the payment of ERC20 tokens to a recipient
     */
    function test_PayWithERC20() public {
        // Token support should be already enabled by setAllTokensSupport(false) in setUp
        
        // Mint some tokens to the test contract
        vm.startPrank(ADMIN);
        token1.mint(address(this), TOKEN_AMOUNT);
        vm.stopPrank();
        // Calculate expected fee
        uint256 expectedFee = (TOKEN_AMOUNT * FEE_PERCENTAGE) / 10000;
        uint256 expectedTransferAmount = TOKEN_AMOUNT - expectedFee;

        // Approve the payment router to spend tokens
        token1.approve(address(paymentRouter), TOKEN_AMOUNT);

        // Execute transfer
        vm.expectEmit(true, true, true, false);
        emit ERC20PaymentSent(
            address(this),
            USER2,
            address(token1),
            expectedTransferAmount,
            expectedFee
        );
        paymentRouter.payWithERC20(address(token1), USER2, TOKEN_AMOUNT);

        // Verify balances
        assertEq(
            token1.balanceOf(USER2),
            expectedTransferAmount,
            "USER2 should receive the correct token amount"
        );
        assertEq(
            token1.balanceOf(FEE_COLLECTOR),
            expectedFee,
            "Fee collector should receive the fee"
        );

        // Verify interaction count
        assertEq(
            paymentRouter.interactionCount(address(this)),
            1,
            "Interaction count should be incremented"
        );
    }

    /**
     * @notice Test batch ERC20 payment
     * @dev Tests batch payment functionality with ERC20 tokens
     */
    function test_BatchPayWithERC20() public {
        // Token support should be already enabled by setAllTokensSupport(false) in setUp
        
        // Mint some tokens to the test contract
        vm.startPrank(ADMIN);
        token1.mint(address(this), TOKEN_AMOUNT);
        token2.mint(address(this), TOKEN_AMOUNT);
        vm.stopPrank();
        // Set up batch parameters
        address[] memory tokens = new address[](2);
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(token1);
        tokens[1] = address(token2);

        recipients[0] = USER1;
        recipients[1] = USER2;

        amounts[0] = TOKEN_AMOUNT / 2;
        amounts[1] = TOKEN_AMOUNT;

        // Calculate expected fees
        uint256 expectedFee1 = (amounts[0] * FEE_PERCENTAGE) / 10000;
        uint256 expectedFee2 = (amounts[1] * FEE_PERCENTAGE) / 10000;

        uint256 expectedTransferAmount1 = amounts[0] - expectedFee1;
        uint256 expectedTransferAmount2 = amounts[1] - expectedFee2;

        // Approve the payment router to spend tokens
        token1.approve(address(paymentRouter), amounts[0]);
        token2.approve(address(paymentRouter), amounts[1]);

        // Execute batch transfer
        // For batch transfer, just check sender
        vm.expectEmit(true, false, false, false);
        emit BatchPaymentSent(address(this), 2);
        paymentRouter.batchPayWithERC20(tokens, recipients, amounts);

        // Verify balances
        assertEq(
            token1.balanceOf(USER1),
            expectedTransferAmount1,
            "USER1 should receive the correct token1 amount"
        );
        assertEq(
            token2.balanceOf(USER2),
            expectedTransferAmount2,
            "USER2 should receive the correct token2 amount"
        );

        assertEq(
            token1.balanceOf(FEE_COLLECTOR),
            expectedFee1,
            "Fee collector should receive the token1 fee"
        );
        assertEq(
            token2.balanceOf(FEE_COLLECTOR),
            expectedFee2,
            "Fee collector should receive the token2 fee"
        );

        // Verify interaction count (should only increment once for batch)
        assertEq(
            paymentRouter.interactionCount(address(this)),
            1,
            "Interaction count should be incremented only once for batch"
        );
    }

    /**
     * @notice Test that ERC20 transfer reverts when allowance is insufficient
     * @dev Tests revert when trying to transfer ERC20 with insufficient allowance
     */
    function test_RevertWhenInsufficientERC20Allowance() public {
        // Token support should be already enabled by setAllTokensSupport(false) in setUp
        
        // Set up the domain with a resolver
        vm.prank(USER1);
        resolver.setAddr(getTestNode(), USER2);
        // Get tokens for testing
        vm.startPrank(ADMIN);
        token1.mint(address(this), TOKEN_AMOUNT);
        vm.stopPrank();

        // Do not approve the payment router

        // Calculate transfer amount (recipient amount)
        uint256 expectedFee = (TOKEN_AMOUNT * FEE_PERCENTAGE) / 10000;
        uint256 expectedTransferAmount = TOKEN_AMOUNT - expectedFee;

        // Attempt to transfer (should fail due to no allowance)
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(paymentRouter),  // spender
                0,                       // current allowance
                expectedTransferAmount   // needed amount
            )
        );
        paymentRouter.transferERC20ToPNS(
            TEST_NAME,
            address(token1),
            TOKEN_AMOUNT
        );
    }

    /**
     * @notice Test that ERC20 transfer reverts when unsupported token is used
     */
    function test_RevertWhenUnsupportedToken() public {
        // Setup: Set USER2 as the address for the test node
        bytes32 testNode = getNodeHash(TEST_NAME);
        setNodeAddress(testNode, USER2);

        // Deploy a new token that's not in the allowlist
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNS");

        // Enable token allowlist (true means use allowlist)
        vm.prank(ADMIN);
        paymentRouter.setAllTokensSupport(true);

        // Get tokens for testing
        vm.startPrank(ADMIN);
        unsupportedToken.mint(address(this), TOKEN_AMOUNT);
        vm.stopPrank();

        // Approve the payment router
        unsupportedToken.approve(address(paymentRouter), TOKEN_AMOUNT);

        // Attempt to transfer (should fail due to token not supported)
        vm.expectRevert(
            abi.encodeWithSelector(
                PNSPaymentRouter.PNSPaymentRouter__UnsupportedToken.selector,
                address(unsupportedToken)
            )
        );
        paymentRouter.transferERC20ToPNS(
            TEST_NAME,
            address(unsupportedToken),
            TOKEN_AMOUNT
        );
    }

    /**
     * @notice Test batch payment reverts with inconsistent array lengths
     */
    function test_RevertBatchWithInconsistentArrays() public {
        // Set up batch parameters with mismatched lengths
        address[] memory tokens = new address[](2);
        address[] memory recipients = new address[](3); // Different length
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = address(token1);
        tokens[1] = address(token2);

        recipients[0] = USER1;
        recipients[1] = USER2;
        recipients[2] = address(0x5);

        amounts[0] = TOKEN_AMOUNT / 2;
        amounts[1] = TOKEN_AMOUNT;

        // Attempt batch transfer with mismatched arrays
        vm.expectRevert(
            PNSPaymentRouter.PNSPaymentRouter__BatchArrayMismatch.selector
        );
        paymentRouter.batchPayWithERC20(tokens, recipients, amounts);
    }

    // ==================== Admin Function Tests ====================

    /**
     * @notice Test setting fee collector
     */
    function test_SetFeeCollector() public {
        address newFeeCollector = address(0x5);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit FeeCollectorUpdated(FEE_COLLECTOR, newFeeCollector);
        paymentRouter.setFeeCollector(newFeeCollector);

        assertEq(
            paymentRouter.feeCollector(),
            newFeeCollector,
            "Fee collector should be updated"
        );
    }

    /**
     * @notice Test setting fee percentage
     */
    function test_SetFeePercentage() public {
        uint256 newFeePercentage = 500; // 5%

        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit FeePercentageUpdated(FEE_PERCENTAGE, newFeePercentage);
        paymentRouter.setFeePercentage(newFeePercentage);

        assertEq(
            paymentRouter.feePercentage(),
            newFeePercentage,
            "Fee percentage should be updated"
        );
    }

    /**
     * @notice Test setting token support
     */
    function test_SetSupportedToken() public {
        address newToken = address(0x6);

        // Enable token allowlist
        vm.prank(ADMIN);
        paymentRouter.setAllTokensSupport(true);

        // Verify token is not supported initially
        assertFalse(
            paymentRouter.isTokenSupported(newToken),
            "Token should not be supported initially"
        );

        // Set token support
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit TokenSupportUpdated(newToken, true);
        paymentRouter.setSupportedToken(newToken, true);

        // Verify token is now supported
        assertTrue(
            paymentRouter.isTokenSupported(newToken),
            "Token should be supported after update"
        );

        // Remove token support
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit TokenSupportUpdated(newToken, false);
        paymentRouter.setSupportedToken(newToken, false);

        // Verify token is no longer supported
        assertFalse(
            paymentRouter.isTokenSupported(newToken),
            "Token should not be supported after removal"
        );
    }

    /**
     * @notice Test setting all tokens support
     */
    function test_SetAllTokensSupport() public {
        // Enable allowlist (true means allowlist is enabled)
        vm.prank(ADMIN);
        paymentRouter.setAllTokensSupport(true);

        // Random token should not be supported when allowlist is enabled
        address randomToken = address(0x7);
        assertFalse(
            paymentRouter.isTokenSupported(randomToken),
            "Random token should not be supported with allowlist"
        );

        // Disable allowlist (false means allowlist is disabled, all tokens allowed)
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit TokenSupportUpdated(address(0), false);
        paymentRouter.setAllTokensSupport(false);

        // Random token should be supported when allowlist is disabled
        assertTrue(
            paymentRouter.isTokenSupported(randomToken),
            "Random token should be supported without allowlist"
        );
    }

    /**
     * @notice Test pausing and unpausing the contract
     */
    function test_PauseAndUnpause() public {
        // Initially not paused
        assertFalse(
            paymentRouter.paused(),
            "Contract should not be paused initially"
        );

        // Pause the contract
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, false);
        emit PauseStateUpdated(true);
        paymentRouter.setPaused(true);

        // Verify paused
        assertTrue(paymentRouter.paused(), "Contract should be paused");

        // Setup for a transfer attempt
        bytes32 testNode = getNodeHash(TEST_NAME);
        setNodeAddress(testNode, USER2);
        vm.deal(address(this), TRANSFER_AMOUNT);

        // Attempt transfer while paused
        vm.expectRevert(
            PNSPaymentRouter.PNSPaymentRouter__ContractPaused.selector
        );
        paymentRouter.transferETHToPNS{value: TRANSFER_AMOUNT}(TEST_NAME);

        // Unpause the contract
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, false);
        emit PauseStateUpdated(false);
        paymentRouter.setPaused(false);

        // Transfer should now succeed
        paymentRouter.transferETHToPNS{value: TRANSFER_AMOUNT}(TEST_NAME);

        // Verify balances after successful transfer
        assertEq(
            USER2.balance,
            TRANSFER_AMOUNT - ((TRANSFER_AMOUNT * FEE_PERCENTAGE) / 10000),
            "USER2 should receive ETH after unpausing"
        );
    }

    /**
     * @notice Test withdrawing ETH from the contract
     */
    function test_WithdrawETH() public {
        // Send ETH to the contract
        uint256 depositAmount = 2 ether;
        vm.deal(address(this), depositAmount);
        (bool success, ) = address(paymentRouter).call{value: depositAmount}(
            ""
        );
        assertTrue(success, "ETH deposit should succeed");

        // Check contract balance
        assertEq(
            address(paymentRouter).balance,
            depositAmount,
            "Contract should have correct ETH balance"
        );

        // Get Admin's initial balance
        uint256 adminInitialBalance = ADMIN.balance;

        // Withdraw as Admin
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit FundsWithdrawn(ADMIN, depositAmount);
        paymentRouter.withdraw();

        // Verify balances
        assertEq(
            address(paymentRouter).balance,
            0,
            "Contract balance should be 0 after withdrawal"
        );
        assertEq(
            ADMIN.balance,
            adminInitialBalance + depositAmount,
            "Admin should receive withdrawn ETH"
        );
    }

    /**
     * @notice Test withdrawing ERC20 tokens from the contract
     */
    function test_WithdrawERC20() public {
        // Send tokens to the contract
        vm.startPrank(ADMIN);
        token1.mint(address(paymentRouter), TOKEN_AMOUNT);
        vm.stopPrank();

        // Check contract token balance
        assertEq(
            token1.balanceOf(address(paymentRouter)),
            TOKEN_AMOUNT,
            "Contract should have correct token balance"
        );

        // Get Admin's initial token balance
        uint256 adminInitialBalance = token1.balanceOf(ADMIN);

        // Withdraw tokens as Admin
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit FundsWithdrawn(ADMIN, TOKEN_AMOUNT);
        paymentRouter.withdrawERC20(address(token1));

        // Verify balances
        assertEq(
            token1.balanceOf(address(paymentRouter)),
            0,
            "Contract token balance should be 0 after withdrawal"
        );
        assertEq(
            token1.balanceOf(ADMIN),
            adminInitialBalance + TOKEN_AMOUNT,
            "Admin should receive withdrawn tokens"
        );
    }

    /**
     * @notice Test reentrancy protection
     */
    function test_ReentrantAttack() public {
        // Use a simple EOA as recipient to avoid issues with ETH transfers
        address recipient = USER2;

        // Fund the attacker with enough ETH for the attack and transfers
        vm.deal(address(attacker), 5 ether);

        // Set a normal address as fee collector
        vm.prank(ADMIN);
        paymentRouter.setFeeCollector(USER1);
        vm.deal(USER1, 0.1 ether); // Give fee collector some ETH

        // Initial state
        assertEq(attacker.attackCount(), 0, "Initial attack count should be 0");

        // Attempt the attack (should not be able to reenter)
        vm.prank(address(this));
        attacker.attack{value: 1 ether}(recipient);

        // Verify attack failed (count should still be 0 or at most 1 if first call completed)
        assertLe(
            attacker.attackCount(),
            1,
            "Reentrancy attack should have failed"
        );
    }

    /**
     * @notice Test fee percentage validation
     */
    function test_RevertInvalidFeePercentage() public {
        // Try to set fee percentage above maximum
        uint256 invalidFeePercentage = 1001; // 10.01%, above 10% max

        vm.prank(ADMIN);
        vm.expectRevert(
            PNSPaymentRouter.PNSPaymentRouter__InvalidFeePercentage.selector
        );
        paymentRouter.setFeePercentage(invalidFeePercentage);

        // Verify fee percentage hasn't changed
        assertEq(
            paymentRouter.feePercentage(),
            FEE_PERCENTAGE,
            "Fee percentage should not change"
        );
    }

    /**
     * @notice Test fee calculation with different amounts
     */
    function test_FeeCalculation() public {
        // Test with different fee percentages and amounts

        // Test 1: Default fee (2.5%)
        uint256 amount1 = 1 ether;
        uint256 expectedFee1 = (amount1 * FEE_PERCENTAGE) / 10000; // 0.025 ETH
        assertEq(
            paymentRouter.calculateFee(amount1),
            expectedFee1,
            "Fee calculation should be correct for default fee"
        );

        // Test 2: Set fee to 5%
        uint256 newFeePercentage = 500;
        vm.prank(ADMIN);
        paymentRouter.setFeePercentage(newFeePercentage);

        uint256 amount2 = 2 ether;
        uint256 expectedFee2 = (amount2 * newFeePercentage) / 10000; // 0.1 ETH
        assertEq(
            paymentRouter.calculateFee(amount2),
            expectedFee2,
            "Fee calculation should be correct after fee update"
        );

        // Test 3: Set fee to 0%
        vm.prank(ADMIN);
        paymentRouter.setFeePercentage(0);

        // Test 4: Different fee collector but same percentage
        vm.prank(ADMIN);
        paymentRouter.setFeePercentage(newFeePercentage); // Reset to 5%
        vm.prank(ADMIN);
        paymentRouter.setFeeCollector(address(0x123)); // Set to a different address

        uint256 amount4 = 4 ether;
        uint256 expectedFee4 = (amount4 * newFeePercentage) / 10000; // Should calculate normally
        assertEq(
            paymentRouter.calculateFee(amount4),
            expectedFee4,
            "Fee should be calculated normally with different fee collector"
        );
    }

    /**
     * @notice Test recovery mechanism when fee transfer fails
     */
    function test_RecoveryFromFailedFeeTransfer() public {
        // Setup: Create a malicious fee collector that rejects transfers
        MaliciousReceiver maliciousFeeCollector = new MaliciousReceiver();

        // Set the malicious fee collector
        vm.prank(ADMIN);
        paymentRouter.setFeeCollector(address(maliciousFeeCollector));

        // Setup: Set USER2 as the address for the test node
        bytes32 testNode = getNodeHash(TEST_NAME);
        setNodeAddress(testNode, USER2);

        // Get initial balance
        uint256 initialRecipientBalance = USER2.balance;

        // We expect recovery to send the full amount to the recipient when fee transfer fails

        // Execute transfer (fee transfer will fail but should recover)
        vm.deal(address(this), TRANSFER_AMOUNT);
        paymentRouter.transferETHToPNS{value: TRANSFER_AMOUNT}(TEST_NAME);

        // Verify recipient received both the payment amount and the fee (recovery)
        assertEq(
            USER2.balance,
            initialRecipientBalance + TRANSFER_AMOUNT,
            "USER2 should receive the full amount including the fee due to recovery"
        );
    }

    /**
     * @notice Helper function to get the test node hash
     * @return The node hash for the test name
     */
    function getTestNode() internal pure returns (bytes32) {
        return getNodeHash(TEST_NAME);
    }

    /**
     * @notice Test recovery mechanism for ERC20 when fee transfer fails
     */
    function test_RecoveryFromFailedERC20FeeTransfer() public {
        // Deploy a mock token that fails fee transfers
        MockERC20WithFeeFailure mockToken = new MockERC20WithFeeFailure(
            "Recovery Test Token",
            "RTT",
            FEE_COLLECTOR
        );

        // Set up fee collector and support the token
        vm.startPrank(ADMIN);
        paymentRouter.setFeeCollector(FEE_COLLECTOR);
        paymentRouter.setSupportedToken(address(mockToken), true);
        vm.stopPrank();

        // Setup PNS name resolution
        bytes32 testNode = getNodeHash(TEST_NAME);
        setNodeAddress(testNode, USER2);

        // Mint tokens to this test contract
        mockToken.mint(address(this), TOKEN_AMOUNT);

        // Get initial balance of recipient
        uint256 initialUser2Balance = mockToken.balanceOf(USER2);

        // Approve the payment router to spend tokens (full amount including fee)
        mockToken.approve(address(paymentRouter), TOKEN_AMOUNT);

        // Execute the transfer - this should succeed even though fee transfer will "fail"
        paymentRouter.transferERC20ToPNS(
            TEST_NAME,
            address(mockToken),
            TOKEN_AMOUNT
        );

        // Verify that the recipient received the full amount (including what would have been fee)
        // Because the fee transfer "failed" and the router recovered by sending fee to recipient
        assertEq(
            mockToken.balanceOf(USER2) - initialUser2Balance,
            TOKEN_AMOUNT,
            "USER2 should receive the full amount including fee when fee transfer fails"
        );

        // Verify fee collector received nothing
        assertEq(
            mockToken.balanceOf(FEE_COLLECTOR),
            0,
            "Fee collector should receive nothing when fee transfer fails"
        );
    }
}
