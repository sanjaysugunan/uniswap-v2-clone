// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TransferHelper {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TransferHelper__ETHTransferFailed();

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}("");

        if (!success) {
            revert TransferHelper__ETHTransferFailed();
        }
    }
}
