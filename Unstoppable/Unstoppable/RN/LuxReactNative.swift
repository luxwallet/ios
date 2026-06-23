import Foundation
import React

/// Brownfield React Native host for the additive @hanzo/gui screens
/// (shared bundle: @luxwallet/mobile-rn). Lazily creates ONE RCTBridge for the
/// whole app; LoginRNViewController mounts registered components by name. The
/// native wallet's own screens and startup are untouched (keep-native + additive).
///
/// The JS bundle (see ../../../../luxwallet/mobile-rn/index.js) registers:
///   "LuxLogin" -> the SIWx multi-chain login screen.
final class LuxReactNative: NSObject {
    static let shared = LuxReactNative()

    private(set) lazy var bridge: RCTBridge = .init(delegate: self, launchOptions: nil)

    func rootView(moduleName: String, initialProps: [String: Any]? = nil) -> RCTRootView {
        RCTRootView(bridge: bridge, moduleName: moduleName, initialProperties: initialProps)
    }
}

extension LuxReactNative: RCTBridgeDelegate {
    func sourceURL(for _: RCTBridge) -> URL? {
        #if DEBUG
        // Metro dev server (started in ~/work/luxwallet/mobile-rn via `npm start`).
        return RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
        #else
        // Release: the JS bundle baked into the app at build time (CI runs the
        // RN bundle step — see Podfile / build phase in RN/README.md).
        return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
        #endif
    }
}
