// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IRegistrarLike} from "evm-m-extensions/src/swap/interfaces/IRegistrarLike.sol";
import {IMExtension} from "evm-m-extensions/src/interfaces/IMExtension.sol";
import {IMYieldToOne} from "evm-m-extensions/src/projects/yieldToOne/interfaces/IMYieldToOne.sol";
import {IFreezable} from "evm-m-extensions/src/components/freezable/IFreezable.sol";
import {IPausableExtended} from "script/testnet/interfaces/IPausableExtended.sol";

/**
 * @title  Admin
 * @notice Admin script for managing M Extension tokens (YieldToOne)
 * @dev    Provides functions for:
 *         - Enable/disable earning
 *         - Check earning status
 *         - View extension state (M balance, total supply, yield, etc.)
 *         - Claim yield
 *         - Access Control: setYieldRecipient, freeze/unfreeze, pause/unpause
 */
contract Admin is Script {
    // Sepolia addresses (Hub chain)
    address constant SEPOLIA_M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address constant SEPOLIA_REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;

    // Spoke chain addresses (same on Arbitrum Sepolia and OP Sepolia)
    address constant SPOKE_M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;

    // Earners list key
    bytes32 constant EARNERS_LIST = "earners";

    /// @notice Get M Token address for current chain
    function _getMToken() internal view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 11155111) {
            // Sepolia
            return SEPOLIA_M_TOKEN;
        } else if (chainId == 421614) {
            // Arbitrum Sepolia
            return SPOKE_M_TOKEN;
        } else if (chainId == 11155420) {
            // OP Sepolia
            return SPOKE_M_TOKEN;
        } else {
            revert("Unsupported chain");
        }
    }

    /// @notice Get chain name for logging
    function _getChainName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 11155111) return "Sepolia";
        if (chainId == 421614) return "Arbitrum Sepolia";
        if (chainId == 11155420) return "OP Sepolia";
        return "Unknown";
    }

    /* ============ Enable/Disable Earning ============ */

    /// @notice Enable yield earning on a deployed extension
    /// @param extension The address of the deployed extension proxy
    /// @param pk The private key of the caller
    function enableEarning(address extension, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Enabling Yield Earning");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);

        vm.startBroadcast(pk);

        IMExtension(extension).enableEarning();

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Earning enabled successfully!");
        console.log("================================================================================");
    }

    /// @notice Disable yield earning on a deployed extension
    /// @param extension The address of the deployed extension proxy
    /// @param pk The private key of the caller
    function disableEarning(address extension, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Disabling Yield Earning");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);

        vm.startBroadcast(pk);

        IMExtension(extension).disableEarning();

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Earning disabled successfully!");
        console.log("================================================================================");
    }

    /* ============ Status Checks ============ */

    /// @notice Check if yield earning is enabled on a deployed extension
    /// @param extension The address of the deployed extension proxy
    function isEarningEnabled(address extension) external view {
        console.log("================================================================================");
        console.log("Checking Earning Status");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);

        bool isEarning = IMExtension(extension).isEarningEnabled();

        console.log("Is Earning Enabled:", isEarning);

        if (isEarning) {
            console.log("Status: ENABLED");
        } else {
            console.log("Status: DISABLED");
        }
        console.log("================================================================================");
    }

    /// @notice Check if extension is in the TTG earners list (Sepolia only)
    /// @param extension The address of the deployed extension proxy
    function isApprovedEarner(address extension) external view {
        console.log("================================================================================");
        console.log("Checking Approved Earner Status");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Registrar:", SEPOLIA_REGISTRAR);

        // Note: This only works on Sepolia where Registrar is deployed
        require(block.chainid == 11155111, "isApprovedEarner only available on Sepolia");

        bool isApproved = IRegistrarLike(SEPOLIA_REGISTRAR).listContains(EARNERS_LIST, extension);

        console.log("Is Approved Earner:", isApproved);

        if (isApproved) {
            console.log("Status: APPROVED (in earners list)");
        } else {
            console.log("Status: NOT APPROVED (not in earners list)");
            console.log("Action Required: Contact M0 team to add extension to earners list");
        }
        console.log("================================================================================");
    }

    /* ============ Extension State ============ */

    /// @notice Get comprehensive status of extension
    /// @param extension The address of the deployed extension proxy
    function getExtensionStatus(address extension) external view {
        address mToken = _getMToken();

        console.log("================================================================================");
        console.log("Extension Status Report");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension Address:", extension);
        console.log("M Token:", mToken);
        console.log("--------------------------------------------------------------------------------");

        // 1. Check earning status
        bool isEarning = IMExtension(extension).isEarningEnabled();
        console.log("1. Earning Enabled:", isEarning);

        // 2. Check extension's M balance (backing)
        uint256 mBalance = IERC20(mToken).balanceOf(extension);
        console.log("2. M Token Balance (backing):", mBalance);

        // 3. Check total supply of extension tokens
        uint256 totalSupply = IMExtension(extension).totalSupply();
        console.log("3. Total Supply:", totalSupply);

        // 4. Check current index
        uint128 currentIndex = IMExtension(extension).currentIndex();
        console.log("4. Current Index:", currentIndex);

        // 5. Check if in earners list (Sepolia only)
        if (block.chainid == 11155111) {
            bool isApproved = IRegistrarLike(SEPOLIA_REGISTRAR).listContains(EARNERS_LIST, extension);
            console.log("5. Is Approved Earner:", isApproved);
        } else {
            console.log("5. Is Approved Earner: N/A (spoke chain)");
        }

        // 6. Check pause status
        bool pauseStatus = IPausableExtended(extension).paused();
        console.log("6. Is Paused:", pauseStatus);

        // 7. Check yield recipient
        address yieldRecipient = IMYieldToOne(extension).yieldRecipient();
        console.log("7. Yield Recipient:", yieldRecipient);

        console.log("--------------------------------------------------------------------------------");
        console.log("Calculated Values:");
        if (mBalance >= totalSupply) {
            console.log("   Accrued Yield (approx):", mBalance - totalSupply);
        } else {
            console.log("   Warning: M balance < totalSupply (unexpected state)");
        }
        console.log("================================================================================");
    }

    /* ============ Yield Operations ============ */

    /// @notice Claim accrued yield (for YieldToOne extensions)
    /// @param extension The address of the deployed extension proxy
    /// @param pk The private key of the caller
    function claimYield(address extension, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Claiming Yield");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);

        // Check yield before claiming
        uint256 yieldBefore = IMYieldToOne(extension).yield();
        address yieldRecipient = IMYieldToOne(extension).yieldRecipient();
        uint256 recipientBalanceBefore = IERC20(extension).balanceOf(yieldRecipient);

        console.log("--------------------------------------------------------------------------------");
        console.log("Before Claim:");
        console.log("  Accrued Yield:", yieldBefore);
        console.log("  Yield Recipient:", yieldRecipient);
        console.log("  Recipient Balance:", recipientBalanceBefore);

        vm.startBroadcast(pk);

        uint256 claimedAmount = IMYieldToOne(extension).claimYield();

        vm.stopBroadcast();

        // Check balances after claiming
        uint256 yieldAfter = IMYieldToOne(extension).yield();
        uint256 recipientBalanceAfter = IERC20(extension).balanceOf(yieldRecipient);

        console.log("--------------------------------------------------------------------------------");
        console.log("After Claim:");
        console.log("  Claimed Amount:", claimedAmount);
        console.log("  Remaining Yield:", yieldAfter);
        console.log("  Recipient Balance:", recipientBalanceAfter);
        console.log("================================================================================");
    }

    /* ============ Yield Recipient Management ============ */

    /// @notice Set the yield recipient address
    /// @dev Requires YIELD_RECIPIENT_MANAGER_ROLE
    /// @param extension The address of the deployed extension proxy
    /// @param newRecipient The new yield recipient address
    /// @param pk The private key of the caller
    function setYieldRecipient(address extension, address newRecipient, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Setting Yield Recipient");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);
        console.log("New Yield Recipient:", newRecipient);

        address currentRecipient = IMYieldToOne(extension).yieldRecipient();
        console.log("Current Yield Recipient:", currentRecipient);

        vm.startBroadcast(pk);

        IMYieldToOne(extension).setYieldRecipient(newRecipient);

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Yield recipient updated successfully!");
        console.log("================================================================================");
    }

    /* ============ Freeze Management ============ */

    /// @notice Freeze an account
    /// @dev Requires FREEZE_MANAGER_ROLE
    /// @param extension The address of the deployed extension proxy
    /// @param account The account to freeze
    /// @param pk The private key of the caller
    function freeze(address extension, address account, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Freezing Account");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);
        console.log("Account to Freeze:", account);

        bool isFrozenBefore = IFreezable(extension).isFrozen(account);
        console.log("Currently Frozen:", isFrozenBefore);

        vm.startBroadcast(pk);

        IFreezable(extension).freeze(account);

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Account frozen successfully!");
        console.log("================================================================================");
    }

    /// @notice Freeze multiple accounts
    /// @dev Requires FREEZE_MANAGER_ROLE
    /// @param extension The address of the deployed extension proxy
    /// @param accounts The accounts to freeze
    /// @param pk The private key of the caller
    function freezeAccounts(address extension, address[] calldata accounts, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Freezing Multiple Accounts");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);
        console.log("Number of Accounts:", accounts.length);

        vm.startBroadcast(pk);

        IFreezable(extension).freezeAccounts(accounts);

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Accounts frozen successfully!");
        console.log("================================================================================");
    }

    /// @notice Unfreeze an account
    /// @dev Requires FREEZE_MANAGER_ROLE
    /// @param extension The address of the deployed extension proxy
    /// @param account The account to unfreeze
    /// @param pk The private key of the caller
    function unfreeze(address extension, address account, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Unfreezing Account");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);
        console.log("Account to Unfreeze:", account);

        bool isFrozenBefore = IFreezable(extension).isFrozen(account);
        console.log("Currently Frozen:", isFrozenBefore);

        vm.startBroadcast(pk);

        IFreezable(extension).unfreeze(account);

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Account unfrozen successfully!");
        console.log("================================================================================");
    }

    /// @notice Unfreeze multiple accounts
    /// @dev Requires FREEZE_MANAGER_ROLE
    /// @param extension The address of the deployed extension proxy
    /// @param accounts The accounts to unfreeze
    /// @param pk The private key of the caller
    function unfreezeAccounts(address extension, address[] calldata accounts, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Unfreezing Multiple Accounts");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);
        console.log("Number of Accounts:", accounts.length);

        vm.startBroadcast(pk);

        IFreezable(extension).unfreezeAccounts(accounts);

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Accounts unfrozen successfully!");
        console.log("================================================================================");
    }

    /// @notice Check if an account is frozen
    /// @param extension The address of the deployed extension proxy
    /// @param account The account to check
    function isFrozen(address extension, address account) external view {
        console.log("================================================================================");
        console.log("Checking Frozen Status");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Account:", account);

        bool frozen = IFreezable(extension).isFrozen(account);

        console.log("Is Frozen:", frozen);
        console.log("================================================================================");
    }

    /* ============ Pause Management ============ */

    /// @notice Pause the extension contract
    /// @dev Requires PAUSER_ROLE
    /// @param extension The address of the deployed extension proxy
    /// @param pk The private key of the caller
    function pause(address extension, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Pausing Extension");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);

        bool isPausedBefore = IPausableExtended(extension).paused();
        console.log("Currently Paused:", isPausedBefore);

        vm.startBroadcast(pk);

        IPausableExtended(extension).pause();

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Extension paused successfully!");
        console.log("================================================================================");
    }

    /// @notice Unpause the extension contract
    /// @dev Requires PAUSER_ROLE
    /// @param extension The address of the deployed extension proxy
    /// @param pk The private key of the caller
    function unpause(address extension, uint256 pk) external {
        address caller = vm.addr(pk);
        console.log("================================================================================");
        console.log("Unpausing Extension");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("Caller:", caller);

        bool isPausedBefore = IPausableExtended(extension).paused();
        console.log("Currently Paused:", isPausedBefore);

        vm.startBroadcast(pk);

        IPausableExtended(extension).unpause();

        vm.stopBroadcast();

        console.log("--------------------------------------------------------------------------------");
        console.log("Extension unpaused successfully!");
        console.log("================================================================================");
    }

    /// @notice Check if the extension is paused
    /// @param extension The address of the deployed extension proxy
    function isPaused(address extension) external view {
        console.log("================================================================================");
        console.log("Checking Pause Status");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);

        bool paused = IPausableExtended(extension).paused();

        console.log("Is Paused:", paused);
        console.log("================================================================================");
    }

    /* ============ Balance Checks ============ */

    /// @notice Check M token balance of extension (backing)
    /// @param extension The address of the deployed extension proxy
    function checkMBalance(address extension) external view {
        address mToken = _getMToken();

        console.log("================================================================================");
        console.log("M Token Balance Check");
        console.log("================================================================================");
        console.log("Chain:", _getChainName());
        console.log("Extension:", extension);
        console.log("M Token:", mToken);

        uint256 mBalance = IERC20(mToken).balanceOf(extension);
        uint256 totalSupply = IMExtension(extension).totalSupply();

        console.log("M Token Balance:", mBalance);
        console.log("Extension Total Supply:", totalSupply);

        if (mBalance >= totalSupply) {
            console.log("Difference (yield):", mBalance - totalSupply);
            console.log("Status: HEALTHY (M balance >= totalSupply)");
        } else {
            console.log("Warning: M balance < totalSupply!");
            console.log("Deficit:", totalSupply - mBalance);
            console.log("Status: UNHEALTHY");
        }
        console.log("================================================================================");
    }

    /* ============ Help ============ */

    /// @notice Default run function - shows usage info
    function run() public pure {
        console.log("================================================================================");
        console.log("Admin Script - Usage (YieldToOne)");
        console.log("================================================================================");
        console.log("");
        console.log("Supported Chains: Sepolia, Arbitrum Sepolia, OP Sepolia");
        console.log("");
        console.log("All write functions accept a private key (pk) as the last parameter.");
        console.log("Pass $OWNER_PRIVATE_KEY or $USER_PRIVATE_KEY.");
        console.log("");
        console.log("Enable/Disable Earning:");
        console.log("  enableEarning(address,uint256)     - Enable yield earning");
        console.log("  disableEarning(address,uint256)    - Disable yield earning");
        console.log("");
        console.log("Status Checks (view, no pk needed):");
        console.log("  isEarningEnabled(address)  - Check if earning is enabled");
        console.log("  isApprovedEarner(address)  - Check if in TTG earners list (Sepolia only)");
        console.log("  getExtensionStatus(address) - Get comprehensive status");
        console.log("");
        console.log("Yield Operations:");
        console.log("  claimYield(address,uint256)        - Claim accrued yield to treasury");
        console.log("  setYieldRecipient(address,address,uint256) - Set yield recipient");
        console.log("");
        console.log("Freeze Management (FREEZE_MANAGER_ROLE):");
        console.log("  freeze(address,address,uint256)    - Freeze an account");
        console.log("  freezeAccounts(address,address[],uint256) - Freeze multiple accounts");
        console.log("  unfreeze(address,address,uint256)  - Unfreeze an account");
        console.log("  unfreezeAccounts(address,address[],uint256) - Unfreeze multiple accounts");
        console.log("  isFrozen(address,address)  - Check if account is frozen");
        console.log("");
        console.log("Pause Management (PAUSER_ROLE):");
        console.log("  pause(address,uint256)     - Pause the extension");
        console.log("  unpause(address,uint256)   - Unpause the extension");
        console.log("  isPaused(address)          - Check if extension is paused");
        console.log("");
        console.log("Balance Checks:");
        console.log("  checkMBalance(address)     - Check M token backing");
        console.log("");
        console.log("================================================================================");
    }
}
