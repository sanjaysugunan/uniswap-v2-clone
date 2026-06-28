# Uniswap V2 Clone

A from-scratch implementation of the Uniswap V2 protocol built with Solidity and Foundry.

This project is being developed as a learning-focused, production-style implementation of the Uniswap V2 core contracts. The goal is to understand every component of the protocol rather than simply copying the original source code.

> **Status:** 🚧 Work in Progress

---

## Goals

- Build Uniswap V2 completely from scratch
- Understand every design decision in the protocol
- Write production-quality Solidity
- Write comprehensive Foundry unit tests, fuzz tests & invariant tests
- Keep the codebase clean, modular, and well documented

---

## Tech Stack

- Solidity v0.8.24+
- Foundry
- OpenZeppelin
- Forge Standard Library

---

## Project Structure

```text
.
├── src
│   ├── core
│   │   ├── UniswapV2ERC20.sol 
│   │   ├── UniswapV2Factory.sol
│   │   └── UniswapV2Pair.sol
│   ├── interfaces
|   |   ├── IUniswapV2Callee.sol
|   |   ├── IUniswapV2ERC20.sol
|   |   ├── IUniswapV2Factory.sol
|   |   ├── IUniswapV2Pair.sol
│   │   └── IUniswapV2Router.sol
│   ├── libraries
│   │   ├── TransferHelper.sol 
│   │   ├── UniswapV2Library.sol 
│   │   └── UQ112x112.sol 
│   └── periphery
│       └── UniswapV2Router.sol 
├── test
│   ├── unit
│   │   ├── UniswapV2Factory.t.sol
│   │   ├── UniswapV2Pair.t.sol
│   │   └── UniswapV2Router.t.sol
│   ├── fuzz
|   |   ├── 
|   |   ├── 
│   │   └── 
│   └── invariant
│       ├── 
│       ├── 
│       └── 
└── script
```

---

## Features

### Core

- [x] Factory
- [x] Pair
- [x] Router
- [x] Library
- [x] ERC20 LP Token

### Pair

- [x] Mint
- [x] Burn
- [x] Swap
- [x] Skim
- [x] Sync
- [x] Price accumulator updates

### Testing

- [x] Unit tests
- [ ] Fuzz tests
- [ ] Invariant tests
- [ ] Integration tests

---

## Running

Clone the repository

```bash
git clone https://github.com/sanjaysugunan/uniswap-v2-clone.git

cd uniswap-v2-clone
```

Install dependencies

```bash
forge install
```

Build

```bash
forge build
```

Run all tests

```bash
forge test
```

Verbose

```bash
forge test -vvvv
```

Coverage

```bash
forge coverage
```

---

## What I've Learned

This project helped me understand topics such as

- CREATE2 deterministic deployment
- Constant product AMMs
- Liquidity minting and burning
- LP token accounting
- Swap fee mechanics
- Reserve synchronization
- Price accumulators
- Oracle design
- Solidity gas optimizations
- Foundry testing

---

## Notes

This is **not** intended to be a production deployment.

The implementation is written primarily for educational purposes while following production-quality engineering practices where possible.

---

## Roadmap

- [x] Complete Router
- [ ] Flash Swaps
- [x] Library
- [ ] Integration Tests
- [ ] Invariant Testing
- [ ] Documentation improvements
- [ ] Gas optimizations
- [ ] Deployment scripts

---

## References

- Uniswap V2 Whitepaper
- Uniswap V2 Core
- Uniswap V2 Periphery

---

## License

MIT