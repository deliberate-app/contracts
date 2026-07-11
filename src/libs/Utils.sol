// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin-contracts-5.6.1/utils/math/SafeCast.sol";

/// @title Utils
/// @author Michael Heuer
/// @notice A library with math helper functions.
library Utils {
    /// @notice Calculates `floor(value * numerator / denominator)`.
    /// @dev Delegates to OpenZeppelin `Math.mulDiv`, which forms the full-precision (512-bit) product
    /// `value * numerator` before dividing, so it neither overflows nor loses precision. This supersedes the manual
    /// `value / denominator`-based decomposition (see https://ethereum.stackexchange.com/questions/55701) that was
    /// previously used to avoid the intermediate product overflow; that decomposition divided first on purpose and
    /// was exact, but static analyzers flag it as a `divide-before-multiply` false positive.
    /// @param value The value.
    /// @param numerator The numerator.
    /// @param denominator The denominator.
    /// @return result The rounded down result of `value * numerator / denominator`.
    function multiplyByFraction(uint32 value, uint32 numerator, uint32 denominator)
        internal
        pure
        returns (uint32 result)
    {
        result = SafeCast.toUint32(Math.mulDiv(uint256(value), uint256(numerator), uint256(denominator)));
    }

    /// @notice Calculates `ceil(value * numerator / denominator)`.
    /// @dev The rounded-up counterpart of `multiplyByFraction`, used where rounding must favor the pool
    /// (an argument market reserve can never be rounded down to zero).
    /// @param value The value.
    /// @param numerator The numerator.
    /// @param denominator The denominator.
    /// @return result The rounded up result of `value * numerator / denominator`.
    function multiplyByFractionCeil(uint32 value, uint32 numerator, uint32 denominator)
        internal
        pure
        returns (uint32 result)
    {
        result = SafeCast.toUint32(
            Math.mulDiv(uint256(value), uint256(numerator), uint256(denominator), Math.Rounding.Ceil)
        );
    }

    /// @notice Calculates `value * numerator / denominator`, rounded toward zero.
    /// @dev Casting `value` to `int256` forces 256-bit arithmetic so the intermediate product cannot overflow
    /// before the division (multiply-before-divide, exact); `numerator` and `denominator` widen implicitly
    /// (`int64` -> `int256`). OpenZeppelin and Solady provide no signed `mulDiv`, so the widened computation is
    /// done directly here.
    /// @param value The value.
    /// @param numerator The numerator.
    /// @param denominator The denominator.
    /// @return result The result of `value * numerator / denominator`, rounded toward zero.
    function multiplyByFraction(int64 value, int64 numerator, int64 denominator) internal pure returns (int64 result) {
        result = SafeCast.toInt64(int256(value) * int256(numerator) / int256(denominator));
    }

    /// @notice Calculates `value * numerator / denominator`, rounded toward zero, for a signed value and unsigned
    /// weights.
    /// @dev Absorbs the `uint32` -> `int256` widening (Solidity has no implicit signed/unsigned conversion) so callers
    /// can pass `uint32` amounts without casting at the call site. The `int256` arithmetic also keeps the intermediate
    /// product overflow-free.
    /// @param value The value.
    /// @param numerator The numerator.
    /// @param denominator The denominator.
    /// @return result The result of `value * numerator / denominator`, rounded toward zero.
    function multiplyByFraction(int64 value, uint32 numerator, uint32 denominator)
        internal
        pure
        returns (int64 result)
    {
        result = SafeCast.toInt64(int256(value) * int256(uint256(numerator)) / int256(uint256(denominator)));
    }

    /// @notice Splits a value `v` into two parts proportional to `a` and `b`.
    /// @param v The value to split.
    /// @param a The weight of the first part.
    /// @param b The weight of the second part.
    /// @return v1 The first part.
    /// @return v2 The second part.
    function split(uint32 v, uint32 a, uint32 b) internal pure returns (uint32 v1, uint32 v2) {
        v2 = multiplyByFraction({value: v, numerator: b, denominator: a + b});
        v1 = v - v2;
    }
}
