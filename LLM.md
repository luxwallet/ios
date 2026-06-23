# LLM.md — lux iOS wallet (Swift / Xcode)

Guidance for AI agents. Fork lineage: Unstoppable Wallet (Horizontal Systems).

## Build

- Xcode workspace `Wallet.xcworkspace`; project
  `Unstoppable/Unstoppable.xcodeproj`. **Swift Package Manager** (no
  CocoaPods). Min iOS **17**. Team `HC4MCAXJ66`.
- Schemes `Production` / `Development`; configs `Release-Prod` /
  `Debug-Prod` (+ dev). Bundle id `network.lux.wallet` (Prod), display name
  via `APP_DISPLAY_NAME`.
- Per-build config in `Unstoppable/Unstoppable/Configuration/`:
  `App/App-Prod.xcconfig` (bundle id, display name, app-icon name,
  `match`-based provisioning), `Config.xcconfig` (API keys, generated from
  `Config.template.xcconfig`).
- `xcodebuild archive -workspace Wallet.xcworkspace -scheme Production
  -configuration Release-Prod` → `.xcarchive`.

## Native release + signing (`.github/workflows/release.yml`)

Runs on the **arcd macOS fleet** (`dbc-luxfi-macos` — exact-host pin for
Keychain + Xcode + iOS SDKs; `.github/actionlint.yaml` registers the pools).
**No GitHub-hosted runners** (the legacy `deploy_appstore.yml`/`deploy_dev.yml`
use `macos-26` + Fastlane/`match`; they are superseded by `release.yml`).
Triggered by `workflow_dispatch` (brand = all|lux|hanzo|zoo,
`upload-testflight` toggle) or a `v*` tag.

Flow: `build` (per brand: archive **unsigned**, `CODE_SIGNING_ALLOWED=NO`,
brand overrides on the `xcodebuild` line; archive staged so the artifact keeps
the `Lux.xcarchive/` dir) → `sign-ios`
(`hanzoai/ci-signing/.github/workflows/sign-ios.yml@v1`, `secrets: inherit`) →
`publish-release` (signed `.ipa` to a GitHub Release on a tag).

`sign-ios.yml` inputs: `archive-artifact-name`, `archive-name: Lux.xcarchive`,
`export-method: app-store`, `upload-testflight`, `runs-on:
'["dbc-luxfi-macos"]'`. It exports an App-Store-signed `.ipa` using the org
Apple Distribution cert + provisioning profile (`automatic` signing) and
optionally uploads to TestFlight. This replaces the in-repo `match` flow with
the org-wide ci-signing path; API keys are still injected from
`Config.template.xcconfig` at archive time.

## Per-brand baking (lux | hanzo | zoo)

The build runs `@luxwallet/brand`'s `emit-brand <brand>` → writes
`Unstoppable/Unstoppable/Resources/brand.json` (default EVM chain resolved via
`@luxwallet/chains`) + `BRAND_*` env. `xcodebuild` overrides
`APP_DISPLAY_NAME` / `PRODUCT_BUNDLE_IDENTIFIER` (and should override
`ASSETCATALOG_COMPILER_APPICON_NAME` once per-brand icons exist). The bundled
`brand.json` carries the default chain + gateway for the Swift runtime to read.
`@luxwallet/brand` is the ONE source of brand truth.

PREREQUISITES for non-lux brands: bundle ids `network.hanzo.wallet` /
`network.zoo.wallet` need their own App Store app records + provisioning
profiles before they can sign; lux (`network.lux.wallet`) is wired today.
Per-brand app icons (`AppIcon` alternates) are the remaining logo wiring.

## Rules

1. Update THIS file; never create scratch summary files.
2. arcd pools only — never `macos-latest`/`macos-26`.
3. Signing via `hanzoai/ci-signing`; never put a cert/profile/secret in the
   repo (the `match` repo + API-key xcconfig are the only signing inputs, and
   secrets come from org secrets via `secrets: inherit`).
4. Brand selection via `@luxwallet/brand` only.
