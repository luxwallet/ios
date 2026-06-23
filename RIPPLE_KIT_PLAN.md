# XRP / ripple-kit integration plan

Plan to add native XRP (XRP Ledger) support to the Lux wallet (forked Unstoppable
Wallet, iOS / Swift). XRP is a non-EVM, account-based chain — the integration
mirrors the existing **Stellar** kit (`StellarKitManager` + `StellarAdapter`),
which is the closest account-based, non-EVM precedent in this codebase.

This document is a plan only. No crypto kit is authored here. The inert,
clearly-labeled `// XRP: pending ripple-kit` comment markers already added to
`AdapterFactory.swift` and `Core.swift` are the on-ramp; they compile today and
become real code once the two libraries below land.

Line numbers are **approximate, as of this commit** — every edit below shifts
later line numbers, so re-locate by the cited anchor text rather than trusting
the number.

---

## 1. Gating dependency — MarketKit `BlockchainType.ripple`

`BlockchainType` is **owned by MarketKit**, pinned in
`packages/WalletCore/Package.swift` (line ~36):

```swift
.package(url: "https://github.com/horizontalsystems/MarketKit.Swift", exact: "3.6.12"),
```

Every per-chain `switch blockchainType` in this repo dispatches on
`MarketKit.BlockchainType`. There is **no** `.ripple` case in MarketKit 3.6.12
today (verified: zero `.ripple` references exist in the source tree except the
inert markers added in this change). Until MarketKit exposes/whitelists a
`.ripple` case, no `case .ripple:` arm will compile, and the chain cannot be
enabled in the coin/blockchain registry that drives `WalletManager`.

**Gating action (build-time check):** fork to `luxwallet/MarketKit.Swift` (or a
Lux-owned MarketKit) that:
- adds `BlockchainType.ripple` (uid `"ripple"`),
- whitelists XRP in the blockchain/token registry + supported-blockchains list
  so XRP tokens flow through `WalletStorage` / `CoinManager`,
- repoints the `MarketKit.Swift` package URL in `Package.swift` to the fork.

Confirming `.ripple` exists is a **build-time check**: it only resolves once the
forked package is pinned and SPM re-resolves (done in CI, never locally).

---

## 2. New library to author — `luxwallet/ripple-kit-ios`

New Swift package wrapping an XRP Ledger client (e.g.
[XRPLSwift](https://github.com/Transia-RnD/XRPLSwift)) — product name `RippleKit`,
matching the `*Kit` convention of every other chain kit here.

It must satisfy the adapter surface the wallet already expects of an
account-based chain. Model it on `StellarKitManager` /
`StellarAdapter` (the analogous non-EVM, account-based pair):

- **`RippleKitManager`** — mirror `StellarKitManager`
  (`packages/.../Core/Managers/StellarKitManager.swift`):
  `init(restoreStateManager:marketKit:walletManager:)`,
  a `rippleKit(account:) throws -> RippleKit.Kit` factory (derive the XRP keypair
  from `account.type` seed → classic `r...` address), plus a
  `*UpdatedObservable` so `AdapterManager` can refresh on kit changes.
- **`RippleAdapter : IAdapter`** — conform to the balance / send / receive
  adapter protocols the wallet uses (`IBalanceAdapter`, `IDepositAdapter`,
  send + transactions). Native XRP only (no token standard) for v1; XRPL issued
  currencies (trust lines) are a follow-up, analogous to Stellar assets.
- **`RippleTransactionsAdapter : ITransactionsAdapter`** — paginated XRP tx
  history, mirroring `stellarTransactionAdapter(transactionSource:)`.
- Address parsing/validation for the XRP `r...` (base58 + checksum) format.

RPC: route XRP JSON-RPC through the Lux gateway where applicable, consistent
with the EVM gateway pattern (`https://api.lux.network/v1/rpc/<chainId>`) added
in this branch — though XRPL uses its own JSON-RPC/WebSocket shape, so the exact
gateway path is a `ripple-kit-ios` decision, not an EVM `chainId`.

---

## 3. Exact plug points (this repo)

### 3.1 `packages/WalletCore/Package.swift`

**Dependency array** (lines ~13–54). Insert alphabetically between `OneInchKit`
(line ~40) and `reown-swift` (line ~41):

```swift
.package(url: "https://github.com/luxwallet/ripple-kit-ios", exact: "X.Y.Z"),
```

**WalletCore target `dependencies:`** (lines ~58–103). Insert the matching
product between `OneInchKit` (line ~86) and `ReownRouter` (line ~87):

```swift
.product(name: "RippleKit", package: "ripple-kit-ios"),
```

### 3.2 `packages/WalletCore/Sources/WalletCore/Core/Factories/AdapterFactory.swift`

The native-token / token adapter dispatch is the `switch (wallet.token.type,
wallet.token.blockchain.type)` inside `func adapter(wallet:)` (starts line ~172).
The inert marker is in place at line ~266, immediately before `default: ()`
(line ~268). Replace it with a real arm (parallel to `case (.native, .stellar)`
at line ~246 and `(.native, .tron)` at line ~229):

```swift
case (.native, .ripple):
    if let rippleKit = try? rippleKitManager.rippleKit(account: wallet.account) {
        return RippleAdapter(rippleKit: rippleKit)
    }
```

Also add a stored `private let rippleKitManager: RippleKitManager`, an init
param, and a `rippleTransactionsAdapter(transactionSource:)` helper mirroring
`stellarTransactionAdapter(transactionSource:)` (line ~152).

### 3.3 `packages/WalletCore/Sources/WalletCore/Core/Managers/AdapterManager.swift`

Per-chain kit managers are referenced here for refresh/unlink. Add `.ripple`
arms parallel to the Stellar/Tron lines:
- subscribe to the ripple kit's updated observable in `init` (model:
  `tronKitManager.tronKitUpdatedObservable` at line ~64),
- `self.rippleKitManager.rippleKit?.sync()` in `refresh()` (model:
  `stellarKitManager.stellarKit?.sync()` at line ~251),
- a `else if wallet.token.blockchainType == .ripple` branch in `refresh(wallet:)`
  (model: `.stellar` branch at line ~265).
Add the `rippleKitManager` stored property + init param.

### 3.4 `packages/WalletCore/Sources/WalletCore/Core/Managers/RestoreSettingsManager.swift`

XRP needs **no restore birthday** (no `birthdayHeight` — XRPL has no
wallet-birthday scan model, like Stellar/Tron). `RestoreSettingType` (line ~52)
has only `.birthdayHeight`, whose `createdAccountValue(blockchainType:)` returns
`nil` for any chain not in `{.zcash, .monero, .zano}` — so XRP already falls
through to `nil` with **no change required here**. Documented for completeness.

The real construction plug is a new `RippleKitManager` (and, if XRP needs an
EVM-account-style sync à la Tron, a `RippleAccountManager`) in **`Core.swift`** —
see 3.5.

### 3.5 `packages/WalletCore/Sources/WalletCore/Core/Core.swift`

Mirror the Tron/Ton/Stellar manager construction. The inert marker is at line
~257, right after the `stellarKitManager = StellarKitManager(...)` assignment
(line ~254). Replace it with:

```swift
let rippleKitManager = RippleKitManager(restoreStateManager: restoreStateManager, marketKit: marketKit, walletManager: walletManager)
```

(plus a `let rippleKitManager: RippleKitManager` stored property near
`stellarKitManager`, line ~82). Then thread `rippleKitManager:` into the three
arg lists:
- `AdapterFactory(...)` — line ~322,
- `AdapterManager(...)` — line ~338,
- `AppManager(...)` — line ~470 (only if XRP needs lifecycle start/stop like
  `stellarKitManager:`/`solanaKitManager:` passed there at lines ~483–484).

If XRP mirrors Tron's address-sync model, also add a
`rippleAccountManager = RippleAccountManager(...)` next to `tronAccountManager`
(line ~252).

---

## 4. Per-chain `switch blockchainType` sites needing a `.ripple` arm

From `grep -rn "case .tron" packages/WalletCore/Sources/WalletCore`, the
load-bearing dispatch sites (not exhaustive — these are the ones that gate
balance/send/receive/restore and address handling):

| File | Line ~ | Purpose |
|------|--------|---------|
| `Core/Factories/AdapterFactory.swift` | 229 / 266 | adapter dispatch (3.2) |
| `Core/Managers/EvmSyncSourceManager.swift` | 33, 236 | **EVM-only** — XRP does NOT belong here (non-EVM) |
| `Core/Factories/AddressParserFactory.swift` | 74 | address parser registration for the chain |
| `Core/Storage/AccountStorage.swift` | 72, 218 | account-type persistence (if XRP adds an account type) |
| `Models/AccountType.swift` | 206, 248, 314, 396, 447 | account-type description / coding |
| `Extensions/BlockchainType.swift` | 144, 149, 192 | supported-flag, order, token-protocol description |
| `Extensions/Token.swift` | 17 | token-type label |
| `Modules/MultiSwap/Providers/DestinationHelper.swift` | 64 | swap destination (optional for v1) |
| `Modules/MultiSwap/Providers/USwap/USwapMultiSwapProvider.swift` | 483 | swap provider (optional for v1) |
| `Modules/SwapInfo/SwapInfoViewModel.swift` | 202 | explorer tx URL (`livenet.xrpl.org`) |
| `Modules/Wallet/Receive/Address/ReceiveAddressModule.swift` | 102 | receive-address view |
| `Modules/Watch/WatchViewModel.swift` | 193, 247 | watch-only account support |
| `Modules/ManageAccount/EvmAddress/PublicAddressViewController.swift` | 111 | public-address title (non-EVM path) |

**Minimum viable XRP (balance + send + receive):** 3.1, 3.2, 3.3, 3.5,
`AddressParserFactory.swift:74`, `BlockchainType.swift` (144/149/192),
`Token.swift:17`, `ReceiveAddressModule.swift:102`, `SwapInfoViewModel.swift:202`.
Swap (`DestinationHelper`, `USwapMultiSwapProvider`) and watch-only
(`WatchViewModel`) are follow-ups.

---

## 5. Order of operations

1. Fork + pin `luxwallet/MarketKit.Swift` exposing `.ripple` (gating dep, §1).
2. Author + publish `luxwallet/ripple-kit-ios` (`RippleKit`, §2).
3. Add both to `Package.swift` (§3.1).
4. Replace the two inert markers with real code; add the `.ripple` switch arms
   from §4 (§3.2–3.5).
5. CI build + on-device verify (sign-in, balance, receive address, send). Never
   build locally per repo policy.
