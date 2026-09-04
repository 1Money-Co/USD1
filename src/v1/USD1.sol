// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {MYieldToOneForcedTransfer} from "evm-m-extensions/src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";

/**
 * @title  USD1
 * @notice USD1 Extension using MYieldToOneForcedTransfer model.
 *         All yield goes to a single designated recipient (treasury).
 *         Includes force transfer functionality for compliance.
 */
contract USD1 is MYieldToOneForcedTransfer {
    /* ============ Constructor ============ */

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     * @notice Constructs USD1 Implementation contract
     * @param  mToken_       The address of $M token.
     * @param  swapFacility_ The address of Swap Facility.
     */
    constructor(address mToken_, address swapFacility_) MYieldToOneForcedTransfer(mToken_, swapFacility_) {}

    /* ============ Internal Functions ============ */

    /**
     * @dev   Hook called before claiming yield.
     *        Restricts yield claiming to accounts with YIELD_RECIPIENT_MANAGER_ROLE.
     *        This allows yield to be claimed even when the contract is paused.
     */
    function _beforeClaimYield() internal view override onlyRole(YIELD_RECIPIENT_MANAGER_ROLE) {}
}
