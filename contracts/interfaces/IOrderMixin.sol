// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@1inch/solidity-utils/contracts/libraries/AddressLib.sol";
import "../libraries/MakerTraitsLib.sol";
import "../libraries/TakerTraitsLib.sol";

/**
 * @title IOrderMixin
 * @notice Interface for order processing logic in the 1inch Limit Order Protocol.
 */
interface IOrderMixin {
    struct Order {
        uint256 salt;
        Address maker;
        Address receiver;
        Address makerAsset;
        Address takerAsset;
        uint256 makingAmount;
        uint256 takingAmount;
        MakerTraits makerTraits;
    }

    error InvalidatedOrder();
    error PrivateOrder();
    error BadSignature();
    error OrderExpired();
    error SwapWithZeroAmount();
    error PartialFillNotAllowed();
    error TakingAmountTooHigh();
    error TransferFromMakerToTakerFailed();
    error TransferFromTakerToMakerFailed();

    /**
     * @notice Emitted when order gets filled
     * @param orderHash Hash of the order
     * @param remainingAmount Amount of the maker asset that remains to be filled
     */
    event OrderFilled(
        bytes32 orderHash,
        uint256 remainingAmount
    );

    /**
     * @notice Emitted when order without `useBitInvalidator` gets cancelled
     * @param orderHash Hash of the order
     */
    event OrderCancelled(
        bytes32 orderHash
    );

    /**
     * @notice Emitted when order with `useBitInvalidator` gets cancelled
     * @param maker Maker address
     * @param slotIndex Slot index that was updated
     * @param slotValue New slot value
     */
    event BitInvalidatorUpdated(
        address indexed maker,
        uint256 slotIndex,
        uint256 slotValue
    );

    /**
     * @notice Cancels order's quote
     * @param makerTraits Order makerTraits
     * @param orderHash Hash of the order to cancel
     */
    function cancelOrder(MakerTraits makerTraits, bytes32 orderHash) external;

    /**
     * @notice Same as `fillOrder` but allows to specify arguments that are used by the taker.
     * @param order Order quote to fill
     * @param r R component of signature
     * @param vs VS component of signature
     * @param amount Taker amount to fill
     * @param takerTraits Specifies threshold as maximum allowed takingAmount when takingAmount is zero, otherwise specifies
     * minimum allowed makingAmount. The 2nd (0 based index) highest bit specifies whether taker wants to skip maker's permit.
     * @param args Arguments that are used by the taker (target, extension, interaction, permit)
     * @return makingAmount Actual amount transferred from maker to taker
     * @return takingAmount Actual amount transferred from taker to maker
     * @return orderHash Hash of the filled order
     */
    function fillOrderArgs(
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        TakerTraits takerTraits,
        bytes calldata args
    ) external payable returns(uint256 makingAmount, uint256 takingAmount, bytes32 orderHash);
}
