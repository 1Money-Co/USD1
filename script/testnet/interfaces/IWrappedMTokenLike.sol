// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/**
 * @title  IWrappedMTokenLike
 * @notice The one Wrapped M function the testnet scripts call.
 * @dev    The full interface lives in m0-foundation/wrapped-m-token, which USD1 does not vendor.
 *         Signature matches IWrappedMToken.wrap(address,uint256) on Sepolia.
 */
interface IWrappedMTokenLike {
    /// @notice Wraps `amount` M from the caller into wM credited to `recipient`.
    /// @return wrapped The amount of wM minted.
    function wrap(address recipient, uint256 amount) external returns (uint240 wrapped);
}
