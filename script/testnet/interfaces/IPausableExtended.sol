// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IPausable} from "evm-m-extensions/src/components/pausable/IPausable.sol";

/**
 * @title  Extended Pausable interface with paused() view function.
 * @author 1Money Team
 * @dev    The library's IPausable doesn't expose paused() from PausableUpgradeable.
 *         This interface adds it for script/admin use.
 */
interface IPausableExtended is IPausable {
    /// @notice Returns whether the contract is paused.
    function paused() external view returns (bool);
}
