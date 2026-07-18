// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FaucetToken} from "./FaucetToken.sol";

contract TokenA is FaucetToken {
    constructor() FaucetToken("Token A", "TKA") {}
}
