// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title TransferHelper
 * @author Sanjay Sugunan
 * @notice Provides helper functions for safely transferring native ETH.
 * @dev Wraps low-level ETH transfers and reverts if the transfer fails.
 *      ERC20 transfers are handled using OpenZeppelin's SafeERC20 library.
 */
library TransferHelper {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TransferHelper__ETHTransferFailed();

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Safely transfers native ETH to a recipient.
     * @dev Performs a low-level call to transfer ETH and reverts if the transfer
     *      fails. This helper is used when unwrapping WETH and refunding excess ETH.
     * @param to The recipient of the ETH.
     * @param value The amount of ETH to transfer.
     */
    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}("");

        if (!success) {
            revert TransferHelper__ETHTransferFailed();
        }
    }
}
