// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMTokenFaucet} from "script/testnet/interfaces/IMTokenFaucet.sol";
import {IWrappedMTokenLike} from "script/testnet/interfaces/IWrappedMTokenLike.sol";
import {ISwapFacility} from "evm-m-extensions/src/swap/interfaces/ISwapFacility.sol";

/**
 * @title  Swap
 * @notice Script for user interactions: swap M/wM <-> Extension tokens
 */
contract Swap is Script {
    // Sepolia addresses
    address constant M_TOKEN_FAUCET = 0x7017C274fe0d4614608070df98Fcd405348D4D95;
    address constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address constant WRAPPED_M = 0x437cc33344a0B27A429f795ff6B469C72698B291;
    address constant SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;

    /* ============ Swap wM -> Extension ============ */

    /// @notice Swap wM tokens to Extension tokens
    /// @param extension The Extension token address
    /// @param amount The amount of wM to swap
    /// @param pk The private key of the caller
    function swapWMToExtension(address extension, uint256 amount, uint256 pk) public {
        address caller = vm.addr(pk);
        vm.startBroadcast(pk);

        console.log("================================================================================");
        console.log("Swapping wM -> Extension");
        console.log("================================================================================");
        console.log("From:", caller);
        console.log("Extension:", extension);
        console.log("Amount:", amount);

        // Check wM balance
        uint256 wmBalance = IERC20(WRAPPED_M).balanceOf(caller);
        console.log("Current wM balance:", wmBalance);
        require(wmBalance >= amount, "Insufficient wM balance");

        // Approve SwapFacility to spend wM
        console.log("Approving SwapFacility...");
        IERC20(WRAPPED_M).approve(SWAP_FACILITY, amount);

        // Swap wM -> Extension
        console.log("Swapping...");
        ISwapFacility(SWAP_FACILITY).swap(WRAPPED_M, extension, amount, caller);

        // Check new balances
        uint256 newWmBalance = IERC20(WRAPPED_M).balanceOf(caller);
        uint256 extensionBalance = IERC20(extension).balanceOf(caller);

        console.log("--------------------------------------------------------------------------------");
        console.log("Swap complete!");
        console.log("New wM balance:", newWmBalance);
        console.log("Extension balance:", extensionBalance);

        vm.stopBroadcast();
    }

    /* ============ Swap Extension -> wM ============ */

    /// @notice Swap Extension tokens back to wM
    /// @param extension The Extension token address
    /// @param amount The amount of Extension to swap
    /// @param pk The private key of the caller
    function swapExtensionToWM(address extension, uint256 amount, uint256 pk) public {
        address caller = vm.addr(pk);
        vm.startBroadcast(pk);

        console.log("================================================================================");
        console.log("Swapping Extension -> wM");
        console.log("================================================================================");
        console.log("From:", caller);
        console.log("Extension:", extension);
        console.log("Amount:", amount);

        // Check Extension balance
        uint256 extensionBalance = IERC20(extension).balanceOf(caller);
        console.log("Current Extension balance:", extensionBalance);
        require(extensionBalance >= amount, "Insufficient Extension balance");

        // Approve SwapFacility to spend Extension
        console.log("Approving SwapFacility...");
        IERC20(extension).approve(SWAP_FACILITY, amount);

        // Swap Extension -> wM
        console.log("Swapping...");
        ISwapFacility(SWAP_FACILITY).swap(extension, WRAPPED_M, amount, caller);

        // Check new balances
        uint256 newExtensionBalance = IERC20(extension).balanceOf(caller);
        uint256 wmBalance = IERC20(WRAPPED_M).balanceOf(caller);

        console.log("--------------------------------------------------------------------------------");
        console.log("Swap complete!");
        console.log("New Extension balance:", newExtensionBalance);
        console.log("wM balance:", wmBalance);

        vm.stopBroadcast();
    }

    /* ============ Swap M -> Extension (Direct) ============ */

    /// @notice Swap M tokens directly to Extension tokens (skips wM wrapping)
    /// @param extension The Extension token address
    /// @param amount The amount of M to swap
    /// @param pk The private key of the caller
    function swapMToExtension(address extension, uint256 amount, uint256 pk) public {
        address caller = vm.addr(pk);
        vm.startBroadcast(pk);

        console.log("================================================================================");
        console.log("Swapping M -> Extension (Direct)");
        console.log("================================================================================");
        console.log("From:", caller);
        console.log("Extension:", extension);
        console.log("Amount:", amount);

        uint256 mBalance = IERC20(M_TOKEN).balanceOf(caller);
        console.log("Current M balance:", mBalance);
        require(mBalance >= amount, "Insufficient M balance");

        console.log("Approving SwapFacility...");
        IERC20(M_TOKEN).approve(SWAP_FACILITY, amount);

        console.log("Swapping via swapInM...");
        ISwapFacility(SWAP_FACILITY).swapInM(extension, amount, caller);

        uint256 newMBalance = IERC20(M_TOKEN).balanceOf(caller);
        uint256 extensionBalance = IERC20(extension).balanceOf(caller);

        console.log("--------------------------------------------------------------------------------");
        console.log("Swap complete!");
        console.log("New M balance:", newMBalance);
        console.log("Extension balance:", extensionBalance);

        vm.stopBroadcast();
    }

    /* ============ Swap Extension -> M (Direct) ============ */

    /// @notice Swap Extension tokens directly to M tokens (skips wM unwrapping)
    /// @param extension The Extension token address
    /// @param amount The amount of Extension to swap
    /// @param pk The private key of the caller
    function swapExtensionToM(address extension, uint256 amount, uint256 pk) public {
        address caller = vm.addr(pk);
        vm.startBroadcast(pk);

        console.log("================================================================================");
        console.log("Swapping Extension -> M (Direct)");
        console.log("================================================================================");
        console.log("From:", caller);
        console.log("Extension:", extension);
        console.log("Amount:", amount);

        uint256 extensionBalance = IERC20(extension).balanceOf(caller);
        console.log("Current Extension balance:", extensionBalance);
        require(extensionBalance >= amount, "Insufficient Extension balance");

        console.log("Approving SwapFacility...");
        IERC20(extension).approve(SWAP_FACILITY, amount);

        console.log("Swapping via swapOutM...");
        ISwapFacility(SWAP_FACILITY).swapOutM(extension, amount, caller);

        uint256 newExtensionBalance = IERC20(extension).balanceOf(caller);
        uint256 mBalance = IERC20(M_TOKEN).balanceOf(caller);

        console.log("--------------------------------------------------------------------------------");
        console.log("Swap complete!");
        console.log("New Extension balance:", newExtensionBalance);
        console.log("M balance:", mBalance);

        vm.stopBroadcast();
    }

    /* ============ Full Flow: Faucet -> M -> Extension (Direct) ============ */

    /// @notice Get M from faucet, then swap directly to Extension (optimized flow)
    /// @param extension The Extension token address
    /// @param amount The amount to process (max 100e6 from faucet)
    /// @param pk The private key of the caller
    function faucetToExtensionDirect(address extension, uint256 amount, uint256 pk) public {
        address caller = vm.addr(pk);
        vm.startBroadcast(pk);

        console.log("================================================================================");
        console.log("Optimized Flow: Faucet -> M -> Extension (Direct)");
        console.log("================================================================================");
        console.log("User:", caller);
        console.log("Extension:", extension);
        console.log("Amount:", amount);

        console.log("--------------------------------------------------------------------------------");
        console.log("Step 1: Getting M from faucet...");
        IMTokenFaucet(M_TOKEN_FAUCET).requestMToken(caller);
        uint256 mBalance = IERC20(M_TOKEN).balanceOf(caller);
        console.log("M Token balance:", mBalance);

        console.log("--------------------------------------------------------------------------------");
        console.log("Step 2: Swapping M directly to Extension...");
        IERC20(M_TOKEN).approve(SWAP_FACILITY, amount);
        ISwapFacility(SWAP_FACILITY).swapInM(extension, amount, caller);

        uint256 finalMBalance = IERC20(M_TOKEN).balanceOf(caller);
        uint256 extensionBalance = IERC20(extension).balanceOf(caller);

        console.log("================================================================================");
        console.log("Flow complete!");
        console.log("================================================================================");
        console.log("Final M balance:", finalMBalance);
        console.log("Final Extension balance:", extensionBalance);

        vm.stopBroadcast();
    }

    /* ============ Full Flow: Faucet -> wM -> Extension ============ */

    /// @notice Get M from faucet, wrap to wM, then swap to Extension (full flow)
    /// @param extension The Extension token address
    /// @param amount The amount to process (max 100e6 from faucet)
    /// @param pk The private key of the caller
    function faucetToExtension(address extension, uint256 amount, uint256 pk) public {
        address caller = vm.addr(pk);
        vm.startBroadcast(pk);

        console.log("================================================================================");
        console.log("Full Flow: Faucet -> wM -> Extension");
        console.log("================================================================================");
        console.log("User:", caller);
        console.log("Extension:", extension);
        console.log("Amount:", amount);

        // Step 1: Get M from faucet
        console.log("--------------------------------------------------------------------------------");
        console.log("Step 1: Getting M from faucet...");
        IMTokenFaucet(M_TOKEN_FAUCET).requestMToken(caller);
        uint256 mBalance = IERC20(M_TOKEN).balanceOf(caller);
        console.log("M Token balance:", mBalance);

        // Step 2: Approve and wrap M to wM
        console.log("--------------------------------------------------------------------------------");
        console.log("Step 2: Wrapping M to wM...");
        IERC20(M_TOKEN).approve(WRAPPED_M, amount);
        uint240 wrappedAmount = IWrappedMTokenLike(WRAPPED_M).wrap(caller, amount);
        console.log("Wrapped amount:", wrappedAmount);

        uint256 wmBalance = IERC20(WRAPPED_M).balanceOf(caller);
        console.log("wM balance:", wmBalance);

        // Step 3: Swap wM to Extension
        console.log("--------------------------------------------------------------------------------");
        console.log("Step 3: Swapping wM to Extension...");
        IERC20(WRAPPED_M).approve(SWAP_FACILITY, amount);
        ISwapFacility(SWAP_FACILITY).swap(WRAPPED_M, extension, amount, caller);

        // Final balances
        uint256 finalWmBalance = IERC20(WRAPPED_M).balanceOf(caller);
        uint256 extensionBalance = IERC20(extension).balanceOf(caller);

        console.log("================================================================================");
        console.log("Flow complete!");
        console.log("================================================================================");
        console.log("Final wM balance:", finalWmBalance);
        console.log("Final Extension balance:", extensionBalance);

        vm.stopBroadcast();
    }

    /* ============ View Functions ============ */

    /// @notice Check all relevant balances
    /// @param extension The Extension token address to check
    /// @param account The address to check balances for
    function checkBalances(address extension, address account) public view {
        console.log("================================================================================");
        console.log("Balance Check");
        console.log("================================================================================");
        console.log("User:", account);
        console.log("M Token:", IERC20(M_TOKEN).balanceOf(account));
        console.log("wM Token:", IERC20(WRAPPED_M).balanceOf(account));
        console.log("Extension:", IERC20(extension).balanceOf(account));
    }

    /// @notice Default run function - shows usage info
    function run() public pure {
        console.log("================================================================================");
        console.log("Swap Script - Usage");
        console.log("================================================================================");
        console.log("");
        console.log("All swap functions accept a private key (pk) parameter.");
        console.log("Pass $OWNER_PRIVATE_KEY or $USER_PRIVATE_KEY as the last argument.");
        console.log("");
        console.log("=== Via wM (Standard DeFi path) ===");
        console.log("");
        console.log("1. swapWMToExtension(address extension, uint256 amount, uint256 pk)");
        console.log("   Swap wM tokens to Extension tokens");
        console.log("");
        console.log("2. swapExtensionToWM(address extension, uint256 amount, uint256 pk)");
        console.log("   Swap Extension tokens back to wM");
        console.log("");
        console.log("3. faucetToExtension(address extension, uint256 amount, uint256 pk)");
        console.log("   Full flow: Faucet -> M -> wM -> Extension");
        console.log("");
        console.log("=== Via M (Direct, gas-optimized) ===");
        console.log("");
        console.log("4. swapMToExtension(address extension, uint256 amount, uint256 pk)");
        console.log("   Swap M tokens directly to Extension (skips wM)");
        console.log("");
        console.log("5. swapExtensionToM(address extension, uint256 amount, uint256 pk)");
        console.log("   Swap Extension tokens directly to M (skips wM)");
        console.log("");
        console.log("6. faucetToExtensionDirect(address extension, uint256 amount, uint256 pk)");
        console.log("   Optimized flow: Faucet -> M -> Extension (skips wM)");
        console.log("");
        console.log("=== Utilities ===");
        console.log("");
        console.log("7. checkBalances(address extension, address account)");
        console.log("   Check M, wM, and Extension balances for an account");
        console.log("");
        console.log("Example:");
        console.log("forge script script/testnet/Swap.s.sol --sig 'swapMToExtension(address,uint256,uint256)' \\");
        console.log("  <EXTENSION> <AMOUNT> $USER_PRIVATE_KEY --rpc-url sepolia --broadcast");
    }
}
