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

    // Custom events for testing and logging
    event TestFillOrderStarted(
        bytes32 orderHash,
        address maker,
        address taker,
        uint256 amount
    );

    event TestFillOrder9Validation(
        address recoveredMaker,
        bool signatureValid
    );

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

        // Emit start event with comprehensive logging
        emit TestFillOrderStarted(
            orderHash,
            maker,
            msg.sender,
            amount
        );

        bool signatureValid = true;
        if (maker == address(0) || maker != ECDSA.recover(orderHash, r, vs)) {
            signatureValid = false;
        }
        address recoverMaker = ECDSA.recover(orderHash, r, vs);
        emit TestFillOrder9Validation(
            recoverMaker,
            signatureValid
        );

        // if (maker == address(0) || maker != ECDSA.recover(orderHash, r, vs)) revert BadSignature();

        makingAmount=0;
        takingAmount=0;
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
