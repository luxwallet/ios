# Brownfield React Native host (additive @hanzo/gui screens) — iOS

Embeds the shared `@luxwallet/mobile-rn` bundle (the `@hanzo/gui` login + future
chrome) into the native iOS wallet **additively** — existing Swift screens are
untouched.

## Swift pieces (in this dir)

| File | Role |
|------|------|
| `LuxReactNative.swift` | One lazy `RCTBridge` for the app; `rootView(moduleName:)` mounts a registered RN component. |
| `LoginRNViewController.swift` | Hosts the `"LuxLogin"` RN component in an `RCTRootView`. |
| `LuxSessionModule.swift` + `.m` | Native↔RN bridge — JS `NativeModules.LuxSession.setSession(...)` persists into `Core.shared.oidcAuthManager` (existing keychain). |

The only edit outside this dir is one public `setSession` (+ a public `init`) on
`WalletCore/.../OidcAuthManager.swift`.

## Launch point (add where you want it)

```swift
let vc = LoginRNViewController()
vc.modalPresentationStyle = .fullScreen
present(vc, animated: true)
```

## CI / build wiring — SPM + CocoaPods coexistence (the real risk)

This project is **SPM-based (no Podfile)**, but React Native's brownfield story
is CocoaPods-first. So CI must introduce a Podfile that integrates RN into the
**existing xcodeproj target** while `WalletCore` stays an SPM package (Pods and
SPM coexist fine in one target):

1. Install the JS bundle deps:
   ```bash
   cd ../../../luxwallet/mobile-rn && npm install   # resolves local @luxwallet/* + @hanzo/gui
   ```
2. Add a `Podfile` at the iOS repo root targeting `Unstoppable`:
   ```ruby
   require_relative '../../luxwallet/mobile-rn/node_modules/react-native/scripts/react_native_pods'
   platform :ios, '17.0'
   target 'Unstoppable' do
     config = use_native_modules!(
       '../../luxwallet/mobile-rn'    # where package.json + node_modules live
     )
     use_react_native!(:path => '../../luxwallet/mobile-rn/node_modules/react-native',
                       :hermes_enabled => true)
   end
   ```
3. `pod install` → henceforth **build `Unstoppable.xcworkspace`, not the .xcodeproj**.
   The new files in this dir + the bridging are picked up by the target; the
   `.m` exposes the Swift module to RN.
4. Add a "Bundle React Native code and images" build phase (release) pointing at
   `../../luxwallet/mobile-rn` so the JS bundle bakes into the app
   (`main.jsbundle`). Hermes is on (see `LuxReactNative.sourceURL`).

If the team prefers to avoid CocoaPods entirely, the alternative is RN's
SPM-artifact route (newer/less-trodden) — but the canonical, lowest-risk path is
the Pods-for-RN + SPM-for-WalletCore split above.

See `~/work/luxwallet/mobile-rn/LLM.md` for the JS side.
TODO: switch `@luxwallet/*` from local paths to published npm once available.
