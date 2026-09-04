// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/// @title  IMTokenFaucet
/// @notice Interface for the M Token Faucet contract on Testnet.
interface IMTokenFaucet {
    /// @notice Requests $M tokens from the faucet.
    /// @param  recipient The address to receive the $M tokens.
    function requestMToken(address recipient) external;
}
