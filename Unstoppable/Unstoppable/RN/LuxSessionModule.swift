import Foundation
import React
import WalletCore

/// Native↔RN session bridge. The @hanzo/gui login screen (in @luxwallet/mobile-rn)
/// calls NativeModules.LuxSession.setSession(...) after a successful SIWx login;
/// we persist it into the EXISTING keychain via Core.shared.oidcAuthManager — so
/// the shared-UI login flows straight into the native wallet's session. Additive:
/// the native wallet keeps its own keystore; this only carries the auth token.
@objc(LuxSession)
final class LuxSessionModule: NSObject {
    @objc static func requiresMainQueueSetup() -> Bool { false }

    @objc(setSession:refreshToken:expiresAt:address:chain:)
    func setSession(
        _ token: String,
        refreshToken: String,
        expiresAt: Double,
        address: String,
        chain: String
    ) {
        let session = OidcSession(
            accessToken: token,
            refreshToken: refreshToken.isEmpty ? nil : refreshToken,
            idToken: nil,
            expiresAt: expiresAt,
            // record the proven wallet identity in the scope field for now.
            scope: "web3:\(chain):\(address)"
        )
        try? Core.shared.oidcAuthManager.setSession(session)
    }

    @objc(getSession:rejecter:)
    func getSession(_ resolve: RCTPromiseResolveBlock, rejecter _: RCTPromiseRejectBlock) {
        resolve(Core.shared.oidcAuthManager.accessToken())
    }

    /// Dismiss the RN host VC from JS after login completes.
    @objc func close() {
        DispatchQueue.main.async {
            UIApplication.shared.topMostViewController()?.dismiss(animated: true)
        }
    }
}

private extension UIApplication {
    func topMostViewController() -> UIViewController? {
        let scene = connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
