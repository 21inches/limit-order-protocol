// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import "./interfaces/ITakerInteraction.sol";
import "./interfaces/IPostInteraction.sol";
import "./interfaces/IOrderMixin.sol";
import "./libraries/Errors.sol";
import "./libraries/TakerTraitsLib.sol";
import "./OrderLib.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title Limit Order mixin
abstract contract OrderMixin is IOrderMixin, EIP712 {
    using OrderLib for IOrderMixin.Order;
    using ExtensionLib for bytes;
    using AddressLib for Address;
    using MakerTraitsLib for MakerTraits;
    using TakerTraitsLib for TakerTraits;

    mapping(address maker => mapping(bytes32 orderHash => bool finished)) private _orderFinished;

    /**
     * @notice See {IOrderMixin-cancelOrder}.
     */
    function cancelOrder(MakerTraits, bytes32 orderHash) public {
        _orderFinished[msg.sender][orderHash] = true;
        emit OrderCancelled(orderHash);
    }

    /**
     * @notice See {IOrderMixin-fillOrderArgs}.
     */
    function fillOrderArgs(
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        TakerTraits takerTraits,
        bytes calldata args
    ) external payable returns(uint256 makingAmount, uint256 takingAmount, bytes32 orderHash) {
        (
            address target,
            bytes calldata extension,
            bytes calldata interaction
        ) = _parseArgs(takerTraits, args);

        // Check signature and apply order/maker permit only on the first fill
        orderHash = order.hash(_domainSeparatorV4());
        uint256 remainingMakingAmount = order.makingAmount;
        address maker = order.maker.get();
        if (maker == address(0) || maker != ECDSA.recover(orderHash, r, vs)) revert BadSignature();

        // Validate order
        {
            (bool valid, bytes4 validationResult) = order.isValidExtension(extension);
            if (!valid) {
                // solhint-disable-next-line no-inline-assembly
                assembly ("memory-safe") {
                    mstore(0, validationResult)
                    revert(0, 4)
                }
            }
        }
        if (!order.makerTraits.isAllowedSender(msg.sender)) revert PrivateOrder();
        if (order.makerTraits.isExpired()) revert OrderExpired();

        // Compute maker and taker assets amount
        makingAmount = amount > remainingMakingAmount ? remainingMakingAmount : amount;
        takingAmount = order.calculateTakingAmount(extension, makingAmount, remainingMakingAmount, orderHash);

        uint256 threshold = takerTraits.threshold();
        if (threshold > 0) {
            // Check rate: takingAmount / makingAmount <= threshold / amount
            if (amount == makingAmount) {  // Gas optimization, no SafeMath.mul()
                if (takingAmount > threshold) revert TakingAmountTooHigh();
            } else {
                if (takingAmount * amount > threshold * makingAmount) revert TakingAmountTooHigh();
            }
        }
        if (!order.makerTraits.allowPartialFills() && makingAmount != order.makingAmount) revert PartialFillNotAllowed();
        unchecked { if (makingAmount * takingAmount == 0) revert SwapWithZeroAmount(); }

        // Invalidate order depending on makerTraits
        _orderFinished[order.maker.get()][orderHash] = true;

        // Pre interaction, where maker can prepare funds interactively
        // deleted to save gas

        // Maker => Taker
        {
            if (!IERC20(order.makerAsset.get()).transferFrom(order.maker.get(), target, makingAmount)) revert TransferFromMakerToTakerFailed();
        }

        if (interaction.length > 19) {
            // proceed only if interaction length is enough to store address
            ITakerInteraction(address(bytes20(interaction))).takerInteraction(
                order, extension, orderHash, msg.sender, makingAmount, takingAmount, remainingMakingAmount, interaction[20:]
            );
        }

        // Taker => Maker
        // deleted to save gas

        // Post interaction, where maker can handle funds interactively
        if (order.makerTraits.needPostInteractionCall()) {
            bytes calldata data = extension.postInteractionTargetAndData();
            address listener = order.maker.get();
            if (data.length > 19) {
                listener = address(bytes20(data));
                data = data[20:];
            }
            IPostInteraction(listener).postInteraction(
                order, extension, orderHash, msg.sender, makingAmount, takingAmount, remainingMakingAmount, data
            );
        }

        emit OrderFilled(orderHash, remainingMakingAmount - makingAmount);
    }

    /**
      * @notice Processes the taker interaction arguments.
      * @param takerTraits The taker preferences for the order.
      * @param args The taker interaction arguments.
      * @return target The address to which the order is filled.
      * @return extension The extension calldata of the order.
      * @return interaction The interaction calldata.
      */
    function _parseArgs(TakerTraits takerTraits, bytes calldata args)
        private
        view
        returns(
            address target,
            bytes calldata extension,
            bytes calldata interaction
        )
    {
        if (takerTraits.argsHasTarget()) {
            target = address(bytes20(args));
            args = args[20:];
        } else {
            target = msg.sender;
        }

        uint256 extensionLength = takerTraits.argsExtensionLength();
        if (extensionLength > 0) {
            extension = args[:extensionLength];
            args = args[extensionLength:];
        } else {
            extension = msg.data[:0];
        }

        uint256 interactionLength = takerTraits.argsInteractionLength();
        if (interactionLength > 0) {
            interaction = args[:interactionLength];
        } else {
            interaction = msg.data[:0];
        }
    }
}
