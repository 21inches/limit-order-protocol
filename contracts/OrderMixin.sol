// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/math/Math.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import "./interfaces/ITakerInteraction.sol";
import "./interfaces/IPreInteraction.sol";
import "./interfaces/IPostInteraction.sol";
import "./interfaces/IOrderMixin.sol";
import "./libraries/Errors.sol";
import "./libraries/TakerTraitsLib.sol";
import "./libraries/BitInvalidatorLib.sol";
import "./libraries/RemainingInvalidatorLib.sol";
import "./OrderLib.sol";

/// @title Limit Order mixin
abstract contract OrderMixin is IOrderMixin, EIP712 {
    using SafeERC20 for IERC20;
    using OrderLib for IOrderMixin.Order;
    using ExtensionLib for bytes;
    using AddressLib for Address;
    using MakerTraitsLib for MakerTraits;
    using TakerTraitsLib for TakerTraits;
    using BitInvalidatorLib for BitInvalidatorLib.Data;
    using RemainingInvalidatorLib for RemainingInvalidator;

    mapping(address maker => BitInvalidatorLib.Data data) private _bitInvalidator;
    mapping(address maker => mapping(bytes32 orderHash => RemainingInvalidator remaining)) private _remainingInvalidator;

    /**
     * @notice See {IOrderMixin-cancelOrder}.
     */
    function cancelOrder(MakerTraits makerTraits, bytes32 orderHash) public {
        if (makerTraits.useBitInvalidator()) {
            uint256 invalidator = _bitInvalidator[msg.sender].massInvalidate(makerTraits.nonceOrEpoch(), 0);
            emit BitInvalidatorUpdated(msg.sender, makerTraits.nonceOrEpoch() >> 8, invalidator);
        } else {
            _remainingInvalidator[msg.sender][orderHash] = RemainingInvalidatorLib.fullyFilled();
            emit OrderCancelled(orderHash);
        }
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
        uint256 remainingMakingAmount = _checkRemainingMakingAmount(order, orderHash);
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
        makingAmount = Math.min(amount, remainingMakingAmount);
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
        _bitInvalidator[order.maker.get()].checkAndInvalidate(order.makerTraits.nonceOrEpoch());

        // Pre interaction, where maker can prepare funds interactively
        if (order.makerTraits.needPreInteractionCall()) {
            bytes calldata data = extension.preInteractionTargetAndData();
            address listener = order.maker.get();
            if (data.length > 19) {
                listener = address(bytes20(data));
                data = data[20:];
            }
            IPreInteraction(listener).preInteraction(
                order, extension, orderHash, msg.sender, makingAmount, takingAmount, remainingMakingAmount, data
            );
        }

        // Maker => Taker
        {
            if (!_callTransferFromWithSuffix(
                order.makerAsset.get(),
                order.maker.get(),
                target,
                makingAmount,
                extension.makerAssetSuffix()
            )) revert TransferFromMakerToTakerFailed();
        }

        if (interaction.length > 19) {
            // proceed only if interaction length is enough to store address
            ITakerInteraction(address(bytes20(interaction))).takerInteraction(
                order, extension, orderHash, msg.sender, makingAmount, takingAmount, remainingMakingAmount, interaction[20:]
            );
        }

        // Taker => Maker
        if (msg.value != 0) revert Errors.InvalidMsgValue();

        address receiver = order.getReceiver();
        if (!_callTransferFromWithSuffix(
            order.takerAsset.get(),
            msg.sender,
            receiver,
            takingAmount,
            extension.takerAssetSuffix()
        )) revert TransferFromTakerToMakerFailed();

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

    /**
      * @notice Checks the remaining making amount for the order.
      * @dev If the order has been invalidated, the function will revert.
      * @param order The order to check.
      * @param orderHash The hash of the order.
      * @return remainingMakingAmount The remaining amount of the order.
      */
    function _checkRemainingMakingAmount(IOrderMixin.Order calldata order, bytes32 orderHash) private view returns(uint256 remainingMakingAmount) {
        if (order.makerTraits.useBitInvalidator()) {
            remainingMakingAmount = order.makingAmount;
        } else {
            remainingMakingAmount = _remainingInvalidator[order.maker.get()][orderHash].remaining(order.makingAmount);
        }
        if (remainingMakingAmount == 0) revert InvalidatedOrder();
    }

    /**
      * @notice Calls the transferFrom function with an arbitrary suffix.
      * @dev The suffix is appended to the end of the standard ERC20 transferFrom function parameters.
      * @param asset The token to be transferred.
      * @param from The address to transfer the token from.
      * @param to The address to transfer the token to.
      * @param amount The amount of the token to transfer.
      * @param suffix The suffix (additional data) to append to the end of the transferFrom call.
      * @return success A boolean indicating whether the transfer was successful.
      */
    function _callTransferFromWithSuffix(address asset, address from, address to, uint256 amount, bytes calldata suffix) private returns(bool success) {
        bytes4 selector = IERC20.transferFrom.selector;
        assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
            let data := mload(0x40)
            mstore(data, selector)
            mstore(add(data, 0x04), from)
            mstore(add(data, 0x24), to)
            mstore(add(data, 0x44), amount)
            if suffix.length {
                calldatacopy(add(data, 0x64), suffix.offset, suffix.length)
            }
            let status := call(gas(), asset, 0, data, add(0x64, suffix.length), 0x0, 0x20)
            success := and(status, or(iszero(returndatasize()), and(gt(returndatasize(), 31), eq(mload(0), 1))))
        }
    }
}
