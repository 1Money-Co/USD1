// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMTokenFaucet} from "script/testnet/interfaces/IMTokenFaucet.sol";
import {IWrappedMTokenLike} from "script/testnet/interfaces/IWrappedMTokenLike.sol";

contract Faucet is Script {
    address constant M_TOKEN_FAUCET = 0x7017C274fe0d4614608070df98Fcd405348D4D95;
    address constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address constant WRAPPED_M = 0x437cc33344a0B27A429f795ff6B469C72698B291;

    /// @notice Request $M from faucet, approve, and wrap into $wM
    /// @param recipient The address to receive the wrapped M tokens
    /// @param amount The amount to wrap (must be <= 100e6 from faucet)
    /// @param pk The private key of the caller
    function getMTokenFaucet(address recipient, uint256 amount, uint256 pk) public {
        address caller = vm.addr(pk);
        vm.startBroadcast(pk);

        // Step 1: Get $M from the M Token Faucet to caller (gives 100 $M)
        console.log("Requesting M tokens from faucet...");
        IMTokenFaucet(M_TOKEN_FAUCET).requestMToken(caller);

        uint256 balance = IERC20(M_TOKEN).balanceOf(caller);
        console.log("M Token balance:", balance);

        // Step 2: Approve WrappedM contract to spend $M
        console.log("Approving WrappedM to spend M tokens...");
        IERC20(M_TOKEN).approve(WRAPPED_M, amount);

        // Step 3: Wrap $M into $wM and send to recipient
        console.log("Wrapping M tokens...");
        uint240 wrappedAmount = IWrappedMTokenLike(WRAPPED_M).wrap(recipient, amount);
        console.log("Wrapped amount:", wrappedAmount);

        vm.stopBroadcast();
    }
}
