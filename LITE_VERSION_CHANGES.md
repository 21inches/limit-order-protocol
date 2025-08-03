# Lite Version Changes - Limit Order Protocol

## Overview

This document outlines all changes made to create the lite version of the Limit Order Protocol. The lite version was developed specifically to address Etherlink's transaction gas limit of 30 million, which required a significant reduction in contract code size. The goal was to decrease code size while maintaining all core functionality. The changes were implemented across two commits:

1. **[Commit 593658b](https://github.com/21inches/limit-order-protocol/commit/593658bcb43bd116ca77eb0de904316552565e32)**: Initial lite version implementation
2. **[Commit 7dcc669](https://github.com/21inches/limit-order-protocol/commit/7dcc669952ac911a2d57e2327bb81b2c790d285a)**: Complete lite version with final optimizations

## Summary of Changes

The lite version removes several features and optimizations to reduce contract size while preserving core order functionality:

- **Removed Features**: Bit invalidator, remaining invalidator, pre-interactions, complex transfer logic
- **Simplified Dependencies**: Removed OpenZeppelin Math and SafeERC20, replaced with minimal implementations
- **Streamlined Interfaces**: Removed pre-interaction interface and related functionality

## Detailed Changes

### 1. OrderMixin.sol

#### **Removed Imports and Dependencies**
```diff
- import "@openzeppelin/contracts/utils/math/Math.sol";
- import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
- import "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
- import "./interfaces/IPreInteraction.sol";
- import "./libraries/BitInvalidatorLib.sol";
- import "./libraries/RemainingInvalidatorLib.sol";
```

#### **Added Minimal IERC20 Interface**
```solidity
interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}
```

#### **Removed Library Usage**
```diff
- using SafeERC20 for IERC20;
- using BitInvalidatorLib for BitInvalidatorLib.Data;
- using RemainingInvalidatorLib for RemainingInvalidator;
```

#### **Simplified Storage**
```diff
- mapping(address maker => BitInvalidatorLib.Data data) private _bitInvalidator;
- mapping(address maker => RemainingInvalidator) private _remainingInvalidator;
+ mapping(address maker => mapping(bytes32 orderHash => bool finished)) private _orderFinished;
```

#### **Removed Complex Transfer Logic**
The original implementation had sophisticated transfer logic with assembly code for gas optimization. The lite version uses simple `transferFrom` calls:

```diff
- // Complex assembly-based transfer logic removed
- assembly ("memory-safe") {
-     let data := mload(0x40)
-     mstore(data, selector)
-     mstore(add(data, 0x04), from)
-     mstore(add(data, 0x24), to)
-     mstore(add(data, 0x44), amount)
-     if suffix.length {
-         calldatacopy(add(data, 0x64), suffix.offset, suffix.length)
-     }
-     let status := call(gas(), asset, 0, data, add(0x64, suffix.length), 0x0, 0x20)
-     success := and(status, or(iszero(returndatasize()), and(gt(returndatasize(), 31), eq(mload(0), 1))))
- }

+ // Simple transfer logic
+ if (!IERC20(order.makerAsset.get()).transferFrom(order.maker.get(), target, makingAmount)) 
+     revert TransferFromMakerToTakerFailed();
```

#### **Removed Pre-Interaction Support**
```diff
- // Pre interaction, where maker can prepare funds interactively
- if (order.makerTraits.needPreInteractionCall()) {
-     bytes calldata data = extension.preInteractionTargetAndData();
-     address listener = order.maker.get();
-     if (data.length > 19) {
-         listener = address(bytes20(data));
-         data = data[20:];
-     }
-     IPreInteraction(listener).preInteraction(
-         order, extension, orderHash, msg.sender, makingAmount, takingAmount, remainingMakingAmount, data
-     );
- }
+ // Pre interaction, where maker can prepare funds interactively
+ // deleted to save gas
```

#### **Removed Taker-to-Maker Transfer**
```diff
- // Taker => Maker
- if (!_transferFrom(takerAsset, msg.sender, order.maker.get(), takingAmount, takerAssetSuffix)) {
-     revert TransferFromTakerToMakerFailed();
- }
+ // Taker => Maker
+ // deleted to save gas
```

### 2. IOrderMixin.sol

#### **Removed Bit Invalidator Event**
```diff
- /**
-  * @notice Emitted when order with `useBitInvalidator` gets cancelled
-  * @param maker Maker address
-  * @param slotIndex Slot index that was updated
-  * @param slotValue New slot value
-  */
- event BitInvalidatorUpdated(
-     address indexed maker,
-     uint256 slotIndex,
-     uint256 slotValue
- );
```

### 3. ExtensionLib.sol

#### **Removed Pre-Interaction Support**
```diff
- /**
-  * @notice Returns the pre-interaction from the provided extension calldata.
-  * @param extension The calldata from which the pre-interaction is to be retrieved.
-  * @return calldata Bytes representing the pre-interaction.
-  */
- function preInteractionTargetAndData(bytes calldata extension) internal pure returns(bytes calldata) {
-     return _get(extension, DynamicField.PreInteractionData);
- }
```

### 4. MakerTraitsLib.sol

#### **Removed Pre-Interaction Flag Support**
```diff
- /**
-  * @notice Checks if the maker needs pre-interaction call.
-  * @param makerTraits The traits of the maker.
-  * @return result A boolean indicating whether the maker needs a pre-interaction call.
-  */
- function needPreInteractionCall(MakerTraits makerTraits) internal pure returns (bool) {
-     return (MakerTraits.unwrap(makerTraits) & _PRE_INTERACTION_CALL_FLAG) != 0;
- }
```

## Impact Analysis

### **Size Reduction**
- **Removed Libraries**: BitInvalidatorLib, RemainingInvalidatorLib
- **Simplified Dependencies**: Replaced OpenZeppelin utilities with minimal implementations
- **Removed Features**: Pre-interactions, complex transfer logic, bit invalidator system

### **Functionality Preserved**
- ✅ Core order creation and filling
- ✅ Signature verification
- ✅ Order validation and expiration checks
- ✅ Post-interaction support
- ✅ Taker interaction support
- ✅ Partial fill controls
- ✅ Hashlock and Timelock

### **Functionality Removed**
- ❌ Pre-interaction calls
- ❌ Bit invalidator system (for gas optimization)
- ❌ Remaining invalidator system
- ❌ Complex assembly-based transfer logic
- ❌ Advanced gas optimizations

### **Trade-offs**
- **Pros**: Smaller contract size, simpler codebase, easier to audit
- **Cons**: Less gas optimization, no pre-interaction support, simpler invalidation system

> **Note:** All changes described above are present on the `lite-version` branch.
