<div align="center">

# 🦄 Uniswap V2 Clone

**A production-style implementation of the Uniswap V2 AMM protocol — built from scratch with Solidity & Foundry.**

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&size=20&duration=2800&pause=800&color=FF007A&center=true&vCenter=true&width=560&lines=x+*+y+%3D+k;Factory+%C2%B7+Pair+%C2%B7+Router+%C2%B7+LP+Token;Unit.+Fuzzed.+Invariant-tested.+Shipped." alt="Typing SVG" />

[![Foundry](https://img.shields.io/badge/built%20with-Foundry-orange?style=flat-square)](https://book.getfoundry.sh/)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.30-363636?style=flat-square&logo=solidity)](https://soliditylang.org/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-4E5EE4?style=flat-square&logo=openzeppelin&logoColor=white)](https://openzeppelin.com/)
[![Deployed](https://img.shields.io/badge/deployed-Sepolia-627EEA?style=flat-square&logo=ethereum&logoColor=white)](#-live-deployment)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](./LICENSE)
[![Status](https://img.shields.io/badge/status-complete-brightgreen?style=flat-square)](#-testing-strategy)

**[🌐 Try it live](https://uniswap-v2-clone-sanjay-sugunan.vercel.app/)** · Frontend repo: [uniswap-v2-frontend](https://github.com/sanjaysugunan/uniswap-v2-frontend)

</div>

---

A from-scratch, line-by-line reimplementation of Uniswap V2 — not a fork, not a copy-paste of the audited source. The goal was to understand *every* design decision in the protocol: why reserves are packed into a single storage slot, why `UQ112x112` fixed-point math exists, why `MINIMUM_LIQUIDITY` gets burned forever, and exactly what happens on-chain, byte by byte, when a swap executes.

**Factory · Pair · Router · LP Token · Libraries — all built, all tested (unit + fuzz + invariant), all deployed live on Sepolia with a working frontend on top.**

---

## 🌐 Live Deployment

The full stack is live and usable end-to-end: connect a wallet on Sepolia, claim test tokens, add liquidity, and swap — all through the [frontend](https://uniswap-v2-clone-sanjay-sugunan.vercel.app/), which talks to these deployed contracts.

**Network:** Sepolia (chain ID `11155111`)

| Contract | Address |
|---|---|
| `UniswapV2Factory` | [`0x96E606463d41DAeFf0246D905013aE0CDC5CCef2`](https://sepolia.etherscan.io/address/0x96E606463d41DAeFf0246D905013aE0CDC5CCef2) |
| `UniswapV2Router` | [`0xb15a4579E05Da61E9aDBE77bdD28479E7f6301A3`](https://sepolia.etherscan.io/address/0xb15a4579E05Da61E9aDBE77bdD28479E7f6301A3) |
| `WETH` | [`0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c`](https://sepolia.etherscan.io/address/0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c) |
| `TokenA` (mock ERC-20) | [`0x3fA373A4dD14D51204Ae9fA4a304d27ace75618b`](https://sepolia.etherscan.io/address/0x3fA373A4dD14D51204Ae9fA4a304d27ace75618b) |
| `TokenB` (mock ERC-20) | [`0xA8fCf35bacd4bb5524E356A58d7Cda632446c37b`](https://sepolia.etherscan.io/address/0xA8fCf35bacd4bb5524E356A58d7Cda632446c37b) |
| `TokenC` (mock ERC-20) | [`0x646151fae8178D2fe68Ef8095129AeB78332979A`](https://sepolia.etherscan.io/address/0x646151fae8178D2fe68Ef8095129AeB78332979A) |

`TokenA`, `TokenB`, and `TokenC` are mock ERC-20s minted for free via the frontend's faucet page — no real funds needed to try the protocol end to end.

---

## 🏗️ Architecture Overview

```
                                  createPair()
                    ┌──────────────┐ ───────────▶   ┌────────────────┐
   User / LP  ────▶ │   Router     │                │    Factory     │
   (swaps,          │  (periphery) │◀────────────   │    (core,      │
    add/remove      │              │  getPair       │     CREATE     │
    liquidity)      └──────┬───────┘                └─────────┬──────┘
                           │                                  │ deployPair
                           │ uses                             ▼
                           │                        ┌──────────────────────┐
                           │                        │  Pair (TokenA/TokenB)│
                           └───────────────────────▶│  reserves + LP token │
                                                    └──────────────────────┘

    Libraries: UniswapV2Library (pure math) · TransferHelper (safe transfers) · UQ112x112 (fixed-point) · Math (min/sqrt)
```

Every `Pair` is simultaneously an **AMM** and an **ERC-20 LP token** — deployed deterministically via `CREATE2` from the `Factory`, so any pair's address is computable off-chain with zero lookups.

---

## 🔄 Core Protocol Flows

<table>
<tr>
<td valign="top" width="33%">

**1. Add Liquidity**
```
User
 ├─ TokenA ─┐
 └─ TokenB ─┤
            ▼
         Router
            ▼
     Pair(A/B) ── mints LP
```

</td>
<td valign="top" width="33%">

**2. Swap**
```
User
  ▼
Token In
  ▼
Router
  ▼
Pair(A/B)
  ▼
Token Out
```

</td>
<td valign="top" width="33%">

**3. Remove Liquidity**
```
User
  ▼
LP Tokens ── burns
  ▼
Router
  ▼
Pair(A/B)
  ▼
TokenA + TokenB
```

</td>
</tr>
</table>

---

## 🧩 Key Components

| Component | Responsibility |
|---|---|
| **`UniswapV2Factory`** | Creates trading pairs via `CREATE2`, maps `token ⇒ token ⇒ pair`, emits `PairCreated` |
| **`UniswapV2Pair`** | Holds reserves, mints/burns LP tokens, executes swaps under `x·y=k`, tracks cumulative prices for TWAP |
| **`UniswapV2ERC20`** | The LP token itself — permit-enabled ERC-20 |
| **`UniswapV2Router`** | User-facing entry point: add/remove liquidity, exact-in/exact-out swaps, multi-hop routing |
| **`UniswapV2Library`** | Pure math — `quote`, `getAmountOut`, `getAmountIn`, `pairFor` (CREATE2 address derivation) |
| **`TransferHelper`** | Safe ERC-20/ETH transfers that don't trust return values |
| **`UQ112x112`** | Fixed-point math for reserve/price accumulator packing |
| **`Math`** | `min`, `sqrt` — used in LP minting math (Uniswap's `sqrt(x*y)` initial mint) |

---

## 📂 Project Structure

```text
.
├── src
│   ├── core
│   │   ├── UniswapV2Factory.sol
│   │   ├── UniswapV2Pair.sol
│   │   └── UniswapV2ERC20.sol
│   ├── interfaces
│   │   ├── IUniswapV2Callee.sol
│   │   ├── IUniswapV2Factory.sol
│   │   ├── IUniswapV2Pair.sol
│   │   ├── IUniswapV2Router.sol
│   │   └── IWETH.sol
│   ├── libraries
│   │   ├── Math.sol
│   │   ├── UQ112x112.sol
│   │   ├── TransferHelper.sol
│   │   └── UniswapV2Library.sol
│   └── periphery
│       └── UniswapV2Router.sol
├── script
│   ├── DeployUniswapV2.s.sol
│   ├── HelperConfig.s.sol
│   └── interactions
│       ├── Interactions.s.sol
│       ├── AddLiquidity.s.sol
│       ├── RemoveLiquidity.s.sol
│       └── Swap.s.sol
├── test
│   ├── unit
│   │   ├── UniswapV2Factory.t.sol
│   │   ├── UniswapV2Pair.t.sol
│   │   ├── UniswapV2RouterLiquidity.t.sol
│   │   └── UniswapV2RouterSwap.t.sol
│   ├── fuzz
│   │   ├── UniswapV2FactoryFuzz.t.sol
│   │   ├── UniswapV2PairFuzz.t.sol
│   │   └── UniswapV2RouterFuzz.t.sol
│   ├── invariant
│   │   ├── Handler.t.sol
│   │   └── UniswapV2Invariant.t.sol
│   └── mocks
│       ├── WETH9.sol
│       └── MockFailedTransfer.sol
└── lib
    ├── forge-std
    ├── openzeppelin-contracts
    └── foundry-devops
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
- [x] Price accumulator updates (TWAP)

</td>
<td valign="top" width="33%">

**Shipped**
- [x] Unit / fuzz / invariant tests
- [x] Deployment & interaction scripts
- [x] Deployed live on Sepolia
- [x] Working frontend on top

</td>
</tr>
</table>

---

## 🔑 The Invariant

The entire protocol's solvency rests on one line:

```solidity
// k must never decrease across any sequence of swaps or liquidity events
assert(reserve0 * reserve1 >= k);
```

The `invariant/` suite (`Handler.t.sol` + `UniswapV2Invariant.t.sol`) drives randomized sequences of adds, removes, and swaps across the system and asserts this holds every time — alongside checks like *the Router never holds a dangling token balance* and *LP token supply always reconciles with underlying reserves*.

---

## 📐 Constant Product Formula

$$x \times y = k$$

Where `x` = reserve of token0, `y` = reserve of token1, `k` = constant (up only, modulo fees). Every swap pays a **0.30% (30 bps)** fee, taken out of the input amount before the constant-product math is applied — which is exactly why `k` trends upward over time instead of staying perfectly flat.

---

## 🧪 Testing Strategy

| Layer | Coverage |
|---|---|
| **Unit** | Factory pair creation, Pair mint/burn/swap accounting, Router liquidity & swap paths |
| **Fuzz** | Factory, Pair, and Router functions fuzzed across randomized amounts, reserves, and edge-case inputs |
| **Invariant** | `k` never decreases · reserves always match token balances · Router never holds assets · LP token accounting stays consistent |
| **Mocks** | `WETH9` for ETH-wrapping paths, `MockFailedTransfer` for testing non-standard/failing ERC-20 behavior |

```bash
forge test              # run everything
forge test -vvvv        # verbose traces
forge coverage          # coverage report
```

---

## 🚀 Getting Started

**Fastest way to try it:** skip local setup entirely and use the **[live frontend](https://uniswap-v2-clone-sanjay-sugunan.vercel.app/)** — connect a wallet on Sepolia, claim test tokens from the faucet page, and start swapping against the deployed contracts above.

To run the contracts locally instead:

**1. Prerequisites** — [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.

**2. Clone & install**
```bash
git clone https://github.com/sanjaysugunan/uniswap-v2-clone.git
cd uniswap-v2-clone
forge install
```

**3. Build**
```bash
forge build
```

**4. Test**
```bash
forge test
```

**5. Deploy locally (Anvil)**
```bash
anvil
forge script script/DeployUniswapV2.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

**6. Interact**
```bash
forge script script/interactions/Interactions.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

---

## 🧠 What I Learned Building This

- `CREATE2` deterministic deployment & off-chain address derivation
- Constant product AMMs (`x·y=k`) and why fees make `k` monotonically increase
- Liquidity minting/burning math, including `MINIMUM_LIQUIDITY` bootstrapping against the zero address
- LP token accounting and `sqrt(x*y)` initial share pricing
- Reserve synchronization (`sync`/`skim`) for handling direct token transfers into a pair
- Price accumulators and TWAP oracle design
- Solidity gas optimizations — packed storage slots, `UQ112x112` fixed-point math
- Foundry methodology end to end: unit → fuzz → stateful invariant testing
- Shipping a full stack: wiring a Next.js/wagmi frontend to a self-deployed AMM on a live testnet

---

## 📝 Notes

This is **not** intended for production deployment or to hold real funds — it has not been audited. It's built for educational depth, following production-quality engineering practices (tests, gas-consciousness, documentation) wherever it made sense to.

---

## 📚 References

- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [Uniswap V2 Core](https://github.com/Uniswap/v2-core)
- [Uniswap V2 Periphery](https://github.com/Uniswap/v2-periphery)

---

## 🔗 Related

- Frontend: [uniswap-v2-frontend](https://github.com/sanjaysugunan/uniswap-v2-frontend)
- Live demo: [uniswap-v2-clone-sanjay-sugunan.vercel.app](https://uniswap-v2-clone-sanjay-sugunan.vercel.app/)

---

## 📄 License

MIT

---

<div align="center">
<sub>⭐ Star this repo if you found it useful · Built by <a href="https://github.com/sanjaysugunan">Sanjay Sugunan</a> · <a href="https://x.com/s4njyy">@s4njyy</a></sub>
</div>