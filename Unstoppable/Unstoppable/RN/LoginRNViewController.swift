import UIKit

/// Hosts the "LuxLogin" @hanzo/gui screen (from @luxwallet/mobile-rn) inside the
/// existing native iOS app. Present it additively from one native entry point:
///
///   let vc = LoginRNViewController()
///   vc.modalPresentationStyle = .fullScreen
///   present(vc, animated: true)
///
/// Existing native login/screens are unaffected.
final class LoginRNViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let rootView = LuxReactNative.shared.rootView(moduleName: "LuxLogin")
        rootView.frame = view.bounds
        rootView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(rootView)
    }
}
