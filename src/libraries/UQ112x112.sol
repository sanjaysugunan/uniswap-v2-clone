// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title UQ112x112
 * @author Sanjay Sugunan
 * @notice Library for 112.112-bit fixed-point arithmetic.
 * @dev Represents unsigned binary fixed-point numbers with 112 integer bits
 *      and 112 fractional bits. Used by Uniswap V2 for cumulative price
 *      calculations in the TWAP oracle.
 */
library UQ112x112 {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint224 constant Q112 = 2 ** 112;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Encodes a uint112 as a UQ112x112 fixed-point number.
     * @dev Multiplies the input by 2^112 to shift it into fixed-point representation.
     *      The multiplication cannot overflow because the input is limited to uint112.
     * @param y The unsigned integer to encode.
     * @return z The encoded UQ112x112 fixed-point value.
     */
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    /**
     * @notice Divides a UQ112x112 fixed-point number by an unsigned integer.
     * @dev Preserves the fixed-point representation while performing the division.
     * @param x The UQ112x112 fixed-point value.
     * @param y The unsigned integer divisor.
     * @return z The resulting UQ112x112 fixed-point value.
     */
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
