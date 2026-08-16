import UIKit

/// Applies Bricolage Grotesque to UIKit-backed chrome that SwiftUI's `.font()`
/// modifier can't reach:
/// - Navigation bar titles (inline + large)
/// - Tab bar item titles
///
/// Called once from `KeptApp.init()`. If a Bricolage weight isn't loaded (e.g.
/// the .ttf failed to register), falls back silently to the system font — no
/// crash, chrome just renders in SF Pro.
enum BricolageAppearance {
    static func apply() {
        // MARK: - Navigation bars
        let nav = UINavigationBar.appearance()

        if let semibold = UIFont(name: "BricolageGrotesque24pt-SemiBold", size: 17) {
            nav.titleTextAttributes = [
                .font: semibold
            ]
        }

        if let bold = UIFont(name: "BricolageGrotesque24pt-Bold", size: 34) {
            nav.largeTitleTextAttributes = [
                .font: bold
            ]
        }

        // MARK: - Tab bars

        let tab = UITabBarItem.appearance()
        if let medium = UIFont(name: "BricolageGrotesque24pt-Medium", size: 10) {
            tab.setTitleTextAttributes([.font: medium], for: .normal)
            tab.setTitleTextAttributes([.font: medium], for: .selected)
        }
    }
}
