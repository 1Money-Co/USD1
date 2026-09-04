// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MYieldToOneForcedTransfer} from "evm-m-extensions/src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";
import {IForcedTransferable} from "evm-m-extensions/src/components/forcedTransferable/IForcedTransferable.sol";
import {IFreezable} from "evm-m-extensions/src/components/freezable/IFreezable.sol";
import {IPausable} from "evm-m-extensions/src/components/pausable/IPausable.sol";
import {USD1} from "src/v1/USD1.sol";

/**
 * @title  USD1 Unit Tests
 * @notice Tests for USD1 contract functionality
 * @dev    Tests that require M Token interactions should use fork tests
 */
contract USD1Test is Test {
    // Same addresses on Ethereum mainnet and Sepolia
    address constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address constant SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;

    USD1 public implementation;
    USD1 public extension;
    address public proxyAdmin;

    address public admin;
    address public yieldRecipient;
    address public freezeManager;
    address public yieldRecipientManager;
    address public pauser;
    address public forcedTransferManager;
    address public user;

    function setUp() public {
        // Setup test accounts
        admin = makeAddr("admin");
        yieldRecipient = makeAddr("yieldRecipient");
        freezeManager = makeAddr("freezeManager");
        yieldRecipientManager = makeAddr("yieldRecipientManager");
        pauser = makeAddr("pauser");
        forcedTransferManager = makeAddr("forcedTransferManager");
        user = makeAddr("user");
        proxyAdmin = makeAddr("proxyAdmin");

        // Deploy implementation
        implementation = new USD1(M_TOKEN, SWAP_FACILITY);
    }

    /* ============ Helper Functions ============ */

    function _initData(
        address yieldRecipient_,
        address admin_,
        address freezeManager_,
        address yieldRecipientManager_,
        address pauser_,
        address forcedTransferManager_
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            MYieldToOneForcedTransfer.initialize.selector,
            "Test Extension",
            "TEXT",
            yieldRecipient_,
            admin_,
            freezeManager_,
            yieldRecipientManager_,
            pauser_,
            forcedTransferManager_
        );
    }

    function _deployAndInitialize() internal returns (USD1) {
        bytes memory initData =
            _initData(yieldRecipient, admin, freezeManager, yieldRecipientManager, pauser, forcedTransferManager);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initData);
        return USD1(address(proxy));
    }

    function _mockMTokenBalance(address account, uint256 amount) internal {
        vm.mockCall(M_TOKEN, abi.encodeWithSignature("balanceOf(address)", account), abi.encode(amount));
    }

    /* ============ Constructor Tests ============ */

    function test_Constructor() public view {
        // Implementation should be deployed
        assertGt(address(implementation).code.length, 0);
    }

    function test_ConstructorSetsImmutables() public {
        // Create a new implementation and verify it deploys
        USD1 newImpl = new USD1(M_TOKEN, SWAP_FACILITY);
        assertGt(address(newImpl).code.length, 0);
    }

    /* ============ Initialization Tests ============ */

    function test_Initialize() public {
        extension = _deployAndInitialize();

        assertEq(extension.name(), "Test Extension");
        assertEq(extension.symbol(), "TEXT");
        assertEq(extension.yieldRecipient(), yieldRecipient);
        assertEq(extension.totalSupply(), 0);
    }

    function test_RevertWhen_InitializeWithZeroAdmin() public {
        bytes memory initData =
            _initData(yieldRecipient, address(0), freezeManager, yieldRecipientManager, pauser, forcedTransferManager);

        vm.expectRevert();
        new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initData);
    }

    function test_RevertWhen_InitializeWithZeroYieldRecipientManager() public {
        bytes memory initData =
            _initData(yieldRecipient, admin, freezeManager, address(0), pauser, forcedTransferManager);

        vm.expectRevert();
        new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initData);
    }

    function test_RevertWhen_InitializeWithZeroYieldRecipient() public {
        bytes memory initData =
            _initData(address(0), admin, freezeManager, yieldRecipientManager, pauser, forcedTransferManager);

        vm.expectRevert();
        new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initData);
    }

    function test_RevertWhen_InitializeWithZeroFreezeManager() public {
        bytes memory initData =
            _initData(yieldRecipient, admin, address(0), yieldRecipientManager, pauser, forcedTransferManager);

        vm.expectRevert(IFreezable.ZeroFreezeManager.selector);
        new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initData);
    }

    function test_RevertWhen_InitializeWithZeroPauser() public {
        bytes memory initData =
            _initData(yieldRecipient, admin, freezeManager, yieldRecipientManager, address(0), forcedTransferManager);

        vm.expectRevert(IPausable.ZeroPauser.selector);
        new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initData);
    }

    function test_RevertWhen_InitializeWithZeroForcedTransferManager() public {
        bytes memory initData =
            _initData(yieldRecipient, admin, freezeManager, yieldRecipientManager, pauser, address(0));

        vm.expectRevert(IForcedTransferable.ZeroForcedTransferManager.selector);
        new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initData);
    }

    function test_RevertWhen_InitializeTwice() public {
        extension = _deployAndInitialize();

        vm.expectRevert();
        extension.initialize(
            "Test Extension 2",
            "TEXT2",
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );
    }

    /* ============ ERC20 Metadata Tests ============ */

    function test_Name() public {
        extension = _deployAndInitialize();
        assertEq(extension.name(), "Test Extension");
    }

    function test_Symbol() public {
        extension = _deployAndInitialize();
        assertEq(extension.symbol(), "TEXT");
    }

    function test_Decimals() public {
        extension = _deployAndInitialize();
        assertEq(extension.decimals(), 6);
    }

    /* ============ Yield Recipient Tests ============ */

    function test_YieldRecipient() public {
        extension = _deployAndInitialize();
        assertEq(extension.yieldRecipient(), yieldRecipient);
    }

    function test_RevertWhen_SetYieldRecipientByNonManager() public {
        extension = _deployAndInitialize();

        address newRecipient = makeAddr("newRecipient");

        vm.prank(user);
        vm.expectRevert();
        extension.setYieldRecipient(newRecipient);
    }

    /* ============ Balance Tests ============ */

    function test_BalanceOfZero() public {
        extension = _deployAndInitialize();
        assertEq(extension.balanceOf(user), 0);
    }

    function test_TotalSupplyZero() public {
        extension = _deployAndInitialize();
        assertEq(extension.totalSupply(), 0);
    }

    /* ============ Role Tests ============ */

    function test_AdminHasDefaultAdminRole() public {
        extension = _deployAndInitialize();
        assertTrue(extension.hasRole(extension.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_YieldRecipientManagerHasRole() public {
        extension = _deployAndInitialize();
        assertTrue(extension.hasRole(extension.YIELD_RECIPIENT_MANAGER_ROLE(), yieldRecipientManager));
    }

    function test_NonAdminDoesNotHaveRole() public {
        extension = _deployAndInitialize();
        assertFalse(extension.hasRole(extension.DEFAULT_ADMIN_ROLE(), user));
    }

    function test_ForcedTransferManagerHasRole() public {
        extension = _deployAndInitialize();
        assertTrue(extension.hasRole(extension.FORCED_TRANSFER_MANAGER_ROLE(), forcedTransferManager));
    }

    /* ============ Force Transfer Tests ============ */

    function test_RevertWhen_ForceTransferByNonManager() public {
        extension = _deployAndInitialize();

        vm.prank(user);
        vm.expectRevert();
        extension.forceTransfer(user, admin, 100);
    }

    function test_RevertWhen_ForceTransfersWithMismatchedArrays() public {
        extension = _deployAndInitialize();

        address[] memory frozenAccounts = new address[](2);
        frozenAccounts[0] = makeAddr("frozen1");
        frozenAccounts[1] = makeAddr("frozen2");

        address[] memory recipients = new address[](1); // mismatched length
        recipients[0] = admin;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(forcedTransferManager);
        vm.expectRevert(IForcedTransferable.ArrayLengthMismatch.selector);
        extension.forceTransfers(frozenAccounts, recipients, amounts);
    }

    /* ============ Allowance Tests ============ */

    function test_AllowanceZero() public {
        extension = _deployAndInitialize();
        assertEq(extension.allowance(user, admin), 0);
    }

    function test_Approve() public {
        extension = _deployAndInitialize();

        vm.prank(user);
        extension.approve(admin, 1000);

        assertEq(extension.allowance(user, admin), 1000);
    }

    /* ============ Claim Yield Tests (_beforeClaimYield override) ============ */

    function test_ClaimYield_ZeroYield() public {
        extension = _deployAndInitialize();

        // Mock M Token balance of extension to equal totalSupply (0), so yield = 0
        _mockMTokenBalance(address(extension), 0);

        vm.prank(yieldRecipientManager);
        uint256 claimed = extension.claimYield();

        assertEq(claimed, 0);
    }

    function test_ClaimYield_WithYield() public {
        extension = _deployAndInitialize();

        uint256 simulatedYield = 1000e6;

        // Mock M Token balance > totalSupply to simulate accrued yield
        _mockMTokenBalance(address(extension), simulatedYield);

        vm.prank(yieldRecipientManager);
        uint256 claimed = extension.claimYield();

        assertEq(claimed, simulatedYield);
        assertEq(extension.balanceOf(yieldRecipient), simulatedYield);
        assertEq(extension.totalSupply(), simulatedYield);
    }

    function test_ClaimYield_WhilePaused() public {
        extension = _deployAndInitialize();

        uint256 simulatedYield = 1000e6;
        _mockMTokenBalance(address(extension), simulatedYield);

        vm.prank(pauser);
        extension.pause();
        assertTrue(extension.paused());

        // The override gates claimYield on the role only, so pausing does not block it.
        vm.prank(yieldRecipientManager);
        uint256 claimed = extension.claimYield();

        assertEq(claimed, simulatedYield);
        assertEq(extension.balanceOf(yieldRecipient), simulatedYield);
    }

    function test_RevertWhen_ClaimYieldByNonManager() public {
        extension = _deployAndInitialize();

        _mockMTokenBalance(address(extension), 0);

        vm.prank(user);
        vm.expectRevert();
        extension.claimYield();
    }

    function test_RevertWhen_ClaimYieldByAdmin() public {
        extension = _deployAndInitialize();

        _mockMTokenBalance(address(extension), 0);

        // Admin does NOT have YIELD_RECIPIENT_MANAGER_ROLE by default
        vm.prank(admin);
        vm.expectRevert();
        extension.claimYield();
    }

    /* ============ Fuzz Tests ============ */

    function testFuzz_Approve(address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        extension = _deployAndInitialize();

        vm.prank(user);
        extension.approve(spender, amount);

        assertEq(extension.allowance(user, spender), amount);
    }

    function testFuzz_BalanceOfAnyAddress(address account) public {
        extension = _deployAndInitialize();
        // Any address should have 0 balance initially
        assertEq(extension.balanceOf(account), 0);
    }
}
