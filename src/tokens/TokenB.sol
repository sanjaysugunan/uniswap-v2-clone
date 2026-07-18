// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FaucetToken} from "./FaucetToken.sol";

contract TokenB is FaucetToken {
    constructor() FaucetToken("Token B", "TKB") {}
}
