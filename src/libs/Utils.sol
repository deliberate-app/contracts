// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin-contracts-5.6.1/utils/math/SafeCast.sol";

/// @title Utils
/// @author Michael Heuer
/// @notice A library with math and array helper functions.
library Utils {
    /// @notice Removes a value in an array by its index.
    /// @param array The array.
    /// @param i The index to be removed.
    function removeByIndex(uint16[] storage array, uint16 i) internal {
        uint256 length = array.length;
        while (i < length - 1) {
            array[i] = array[i + 1];
            i++;
        }
        array.pop();
    }

    /// @notice Removes a value from an array.
    /// @param array The array.
    /// @param value The value to be removed.
    function removeByValue(uint16[] storage array, uint16 value) internal {
        removeByIndex({array: array, i: findIndex({array: array, value: value})});
    }

    /// @notice Calculates `floor(v * a / b)`.
    /// @dev Delegates to OpenZeppelin `Math.mulDiv`, which forms the full-precision (512-bit) product `v * a` before
    /// dividing, so it neither overflows nor loses precision. This supersedes the manual `v / b`-based decomposition
    /// (see https://ethereum.stackexchange.com/questions/55701) that was previously used to avoid the intermediate
    /// `v * a` overflow; that decomposition divided first on purpose and was exact, but static analyzers flag it as a
    /// `divide-before-multiply` false positive.
    /// @param v The value.
    /// @param a The nominator.
    /// @param b The denominator.
    /// @return result The rounded down result of `v * a / b`.
    function multiplyByFraction(uint32 v, uint32 a, uint32 b) internal pure returns (uint32 result) {
        result = SafeCast.toUint32(Math.mulDiv(uint256(v), uint256(a), uint256(b)));
    }

    /// @notice Calculates `v * a / b`, rounded toward zero.
    /// @dev Casting `v` to `int256` forces 256-bit arithmetic so the intermediate product `v * a` cannot overflow
    /// before the division (multiply-before-divide, exact); `a` and `b` widen implicitly (`int64` -> `int256`).
    /// OpenZeppelin and Solady provide no signed `mulDiv`, so the widened computation is done directly here.
    /// @param v The value.
    /// @param a The nominator.
    /// @param b The denominator.
    /// @return result The result of `v * a / b`, rounded toward zero.
    function multiplyByFraction(int64 v, int64 a, int64 b) internal pure returns (int64 result) {
        result = SafeCast.toInt64(int256(v) * int256(a) / int256(b));
    }

    /// @notice Calculates `v * a / b`, rounded toward zero, for a signed value `v` and unsigned weights `a` and `b`.
    /// @dev Absorbs the `uint32` -> `int256` widening (Solidity has no implicit signed/unsigned conversion) so callers
    /// can pass `uint32` amounts without casting at the call site. The `int256` arithmetic also keeps the intermediate
    /// product overflow-free.
    /// @param v The value.
    /// @param a The nominator.
    /// @param b The denominator.
    /// @return result The result of `v * a / b`, rounded toward zero.
    function multiplyByFraction(int64 v, uint32 a, uint32 b) internal pure returns (int64 result) {
        result = SafeCast.toInt64(int256(v) * int256(uint256(a)) / int256(uint256(b)));
    }

    /// @notice Splits a value `v` into two parts proportional to `a` and `b`.
    /// @param v The value to split.
    /// @param a The weight of the first part.
    /// @param b The weight of the second part.
    /// @return v1 The first part.
    /// @return v2 The second part.
    function split(uint32 v, uint32 a, uint32 b) internal pure returns (uint32 v1, uint32 v2) {
        v2 = multiplyByFraction({v: v, a: b, b: a + b});
        v1 = v - v2;
    }

    /// @notice Finds a value in an array interval using bisection search and returns its index.
    /// @dev Taken from https://gist.github.com/chriseth/0c671e0dac08c3630f47.
    /// @param array The array to be searched.
    /// @param begin The start of the search interval.
    /// @param end The end of the search interval.
    /// @param value The value to be searched.
    /// @return index The index of the value in the array interval.
    function findIndexInInterval(uint16[] memory array, uint16 begin, uint16 end, uint16 value)
        internal
        pure
        returns (uint16 index)
    {
        uint16 len = end - begin;
        if (len == 0 || (len == 1 && array[begin] != value)) {
            return type(uint16).max;
        }
        uint16 mid = begin + len / 2;
        uint16 v = array[mid];
        if (value < v) {
            return findIndexInInterval({array: array, begin: begin, end: mid, value: value});
        } else if (value > v) {
            return findIndexInInterval({array: array, begin: mid + 1, end: end, value: value});
        } else {
            return mid;
        }
    }

    /// @notice Finds a value in an array and returns its index.
    /// @param array The array to be searched.
    /// @param value The value to be searched.
    /// @return index The index of the value in the array.
    function findIndex(uint16[] memory array, uint16 value) internal pure returns (uint16 index) {
        return findIndexInInterval({array: array, begin: 0, end: uint16(array.length), value: value});
    }
}
