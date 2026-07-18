// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {UniswapV2Factory} from "src/core/UniswapV2Factory.sol";
import {IUniswapV2Factory} from "src/interfaces/IUniswapV2Factory.sol";
import {UniswapV2Pair} from "src/core/UniswapV2Pair.sol";
// Oz imports
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory public factory;

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;

    address constant TOKEN_C = address(1);
    address constant TOKEN_D = address(2);

    address constant ZERO_ADDRESS = address(0);

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function setUp() public {
        factory = new UniswapV2Factory();
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
    }

    function testCreatePairRevertsIfSameAddress() public {
        vm.expectRevert(IUniswapV2Factory.UniswapV2Factory__IdenticalAddresses.selector);
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testCreatePairRevertsIfZeroAddress() public {
        vm.expectRevert(IUniswapV2Factory.UniswapV2Factory__ZeroAddress.selector);
        factory.createPair(address(tokenA), ZERO_ADDRESS);
    }

    function testCreatePairRevertsIfPairAlreadyExists() public {
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert(IUniswapV2Factory.UniswapV2Factory__PairExists.selector);
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testCreatePairDeploysPairAtExpectedAddress() public {
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        address computedPairAddress = _computePairAddress(address(tokenA), address(tokenB));

        assertEq(pairAddress, computedPairAddress);
    }

    function testCreatePairSortsTokens() public {
        address pair = factory.createPair(address(tokenB), address(tokenA));

        assertEq(UniswapV2Pair(pair).token0(), address(tokenA));
        assertEq(UniswapV2Pair(pair).token1(), address(tokenB));
    }

    function testCreatePairExpectEmit() public {
        address expectedPair = _computePairAddress(address(tokenA), address(tokenB));
        uint256 pairIndex = 1;
        (address token0, address token1) = _sortTokens(address(tokenA), address(tokenB));

        vm.expectEmit(true, true, true, true, address(factory));
        emit PairCreated(token0, token1, expectedPair, pairIndex);
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testAllPairLengthReturnsLength() public {
        factory.createPair(address(tokenA), address(tokenB)); // 1
        factory.createPair(TOKEN_C, TOKEN_D); // 2
        factory.createPair(address(tokenA), TOKEN_C); // 3
        factory.createPair(address(tokenA), TOKEN_D); // 4

        assertEq(factory.allPairsLength(), 4);
    }

    function testCreatePairSetsGetPair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function testCreatePairAddsPairToAllPairs() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertEq(factory.allPairs(0), pair);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _computePairAddress(address _tokenA, address _tokenB) internal view returns (address) {
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);

        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            address(factory),
                            keccak256(abi.encodePacked(token0, token1)),
                            keccak256(type(UniswapV2Pair).creationCode)
                        )
                    )
                )
            )
        );
    }

    function _sortTokens(address a, address b) internal pure returns (address token0, address token1) {
        return a < b ? (a, b) : (b, a);
    }
}
