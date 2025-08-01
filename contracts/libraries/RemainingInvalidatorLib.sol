// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

type RemainingInvalidator is uint256;

/**
 * @title RemainingInvalidatorLib
 * @notice The library provides a mechanism to invalidate order based on the remaining amount of the order.
 * @dev The remaining amount is used as a nonce to invalidate the order.
 * When order is created, the remaining invalidator is 0.
 * When order is filled, the remaining invalidator is the inverse of the remaining amount.
 */
library RemainingInvalidatorLib {
    /**
     * @notice Calculates the remaining amount for an order.
     * @dev If the order is unknown, the order maker amount is returned.
     * @param invalidator The remaining invalidator for the order.
     * @param orderMakerAmount The amount to return if the order is new.
     * @return result The remaining amount for the order.
     */
    function remaining(RemainingInvalidator invalidator, uint256 orderMakerAmount) internal pure returns(uint256) {
        uint256 value = RemainingInvalidator.unwrap(invalidator);
        if (value == 0) {
            return orderMakerAmount;
        }
        unchecked {
            return ~value;
        }
    }

    /**
     * @notice Provides the remaining invalidator for a fully filled order.
     * @return result The remaining invalidator for a fully filled order.
     */
    function fullyFilled() internal pure returns(RemainingInvalidator) {
        return RemainingInvalidator.wrap(type(uint256).max);
    }
}
