<div align="center">

# 🦄 Uniswap V2 Clone

**A from-scratch implementation of the Uniswap V2 protocol — built with Solidity & Foundry.**

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&size=20&duration=2800&pause=800&color=FF007A&center=true&vCenter=true&width=560&lines=x+*+y+%3D+k;Factory+%C2%B7+Pair+%C2%B7+Router+%C2%B7+LP+Token;Fuzzed.+Invariant-tested.+From+scratch." alt="Typing SVG" />

[![Foundry](https://img.shields.io/badge/built%20with-Foundry-orange?style=flat-square)](https://book.getfoundry.sh/)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.24-363636?style=flat-square&logo=solidity)](https://soliditylang.org/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-4E5EE4?style=flat-square&logo=openzeppelin&logoColor=white)](https://openzeppelin.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](./LICENSE)
[![Status](https://img.shields.io/badge/status-work%20in%20progress-yellow?style=flat-square)](#roadmap)

</div>

---

This is a learning-focused, **production-style** reimplementation of the Uniswap V2 core contracts, built line by line rather than copied. The goal isn't to ship a fork — it's to understand *every* design decision: why reserves are packed the way they are, why the protocol uses `UQ112x112` fixed-point math, why `MINIMUM_LIQUIDITY` exists, and what actually happens on-chain when you swap.

> 🚧 **Status:** Work in Progress — core AMM is fully functional, fuzz/invariant/integration test suites and flash swaps are in active development.

---

## 🎯 Goals

- 🔨 Build Uniswap V2 completely from scratch — no copy-pasting core logic
- 🧠 Understand every design decision in the protocol, not just replicate it
- ✨ Write production-quality, gas-conscious Solidity
- 🧪 Back it with comprehensive Foundry unit, fuzz, and invariant tests
- 🗂️ Keep the codebase clean, modular, and well documented

---

## 🏗️ Architecture

```
                    createPair()
   ┌──────────────┐ ───────────▶ ┌──────────────────┐
   │   Factory     │              │   Pair (per token  │
   │  (CREATE2      │◀───────────│   pair, holds       │
   │   deployer)     │  registry  │   reserves + LP)     │
   └──────────────┘              └────────┬───────────┘
                                            │ mint / burn / swap
                                            ▼
                                  ┌──────────────────────┐
                                  │       Router           │
                                  │  (user-facing entry:   │
                                  │  addLiquidity, swap,    │
                                  │  removeLiquidity)        │
                                  └──────────────────────┘
```

Every `Pair` is an ERC-20 LP token *and* an AMM in one contract — deployed deterministically via `CREATE2` from the `Factory`, so any pair's address can be computed off-chain without a lookup.

---

## 🧰 Tech Stack

<div align="center">

![Solidity](https://img.shields.io/badge/Solidity-363636?style=for-the-badge&logo=solidity&logoColor=white)
![Foundry](https://img.shields.io/badge/Foundry-000000?style=for-the-badge&logo=ethereum&logoColor=white)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-4E5EE4?style=for-the-badge&logo=openzeppelin&logoColor=white)

</div>

- **Solidity** v0.8.24+
- **Foundry** (forge, cast, anvil)
- **OpenZeppelin** contracts
- **Forge Standard Library**

---

## 📂 Project Structure

```text
.
├── src
│   ├── core
│   │   ├── UniswapV2ERC20.sol
│   │   ├── UniswapV2Factory.sol
│   │   └── UniswapV2Pair.sol
│   ├── interfaces
│   │   ├── IUniswapV2Callee.sol
│   │   ├── IUniswapV2ERC20.sol
│   │   ├── IUniswapV2Factory.sol
│   │   ├── IUniswapV2Pair.sol
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
│   └── invariant
└── script
```

---

## ✅ Features

<table>
<tr>
<td valign="top" width="33%">

**Core**
- [x] Factory
- [x] Pair
- [x] Router
- [x] Library
- [x] ERC-20 LP Token

</td>
<td valign="top" width="33%">

**Pair Mechanics**
- [x] Mint
- [x] Burn
- [x] Swap
- [x] Skim
- [x] Sync
- [x] Price accumulator updates

</td>
<td valign="top" width="33%">

**Testing**
- [x] Unit tests
- [ ] Fuzz tests
- [ ] Invariant tests
- [ ] Integration tests

</td>
</tr>
</table>

---

## 🔑 The Invariant

The entire protocol's solvency rests on one line:

```solidity
// k must never decrease across any swap
assert(reserve0 * reserve1 >= k);
```

This is what the invariant test suite (in progress) is built to hammer on — randomized sequences of swaps and liquidity events, checking `k` holds under every path.

---

## 🚀 Running It

```bash
# Clone the repo
git clone https://github.com/sanjaysugunan/uniswap-v2-clone.git
cd uniswap-v2-clone

# Install dependencies
forge install

# Build
forge build

# Run all tests
forge test

# Verbose traces
forge test -vvvv

# Coverage
forge coverage
```

---

## 🗺️ Roadmap

- [x] Complete Router
- [x] Library
- [ ] Flash Swaps
- [ ] Integration Tests
- [ ] Invariant Testing
- [ ] Documentation improvements
- [ ] Gas optimizations
- [ ] Deployment scripts

---

## 🧠 What I've Learned

Building this from scratch (rather than reading the source and moving on) forced a real understanding of:

- `CREATE2` deterministic deployment
- Constant product AMMs (`x·y=k`)
- Liquidity minting and burning mechanics
- LP token accounting & `MINIMUM_LIQUIDITY` bootstrapping
- Swap fee mechanics (the 0.3% fee, in the math)
- Reserve synchronization (`sync` / `skim`)
- Price accumulators & TWAP oracle design
- Solidity gas optimizations (packed storage, `UQ112x112` fixed-point math)
- Foundry testing methodology — unit, fuzz, and invariant

---

## 📝 Notes

This is **not** intended for production deployment. It's written primarily for educational purposes, while following production-quality engineering practices wherever possible — real tests, real gas-consciousness, real documentation.

---

## 📚 References

- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [Uniswap V2 Core](https://github.com/Uniswap/v2-core)
- [Uniswap V2 Periphery](https://github.com/Uniswap/v2-periphery)

---

## 📄 License

MIT

---

<div align="center">
<sub>Built by <a href="https://github.com/sanjaysugunan">Sanjay Sugunan</a> · <a href="https://x.com/s4njyy">@s4njyy</a></sub>
</div>
