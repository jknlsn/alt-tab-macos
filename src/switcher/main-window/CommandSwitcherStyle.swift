import Cocoa

enum CommandSwitcherStyle {
    static func displayedDockLabel(_ dockLabel: String?) -> String? {
        guard let dockLabel = dockLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !dockLabel.isEmpty else { return nil }
        guard Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .commandSwitcher else { return dockLabel }
        if Preferences.commandSwitcherBadgeIndicatorOnly { return "•" }
        if let count = Int(dockLabel) {
            let threshold = Preferences.commandSwitcherLargeBadgeDigits.threshold
            if count > threshold {
                return Preferences.commandSwitcherLargeBadgeStyle == .plus ? "\(threshold)+" : "*"
            }
            return dockLabel
        }
        return Preferences.commandSwitcherHideNonNumericBadges ? "•" : dockLabel
    }

    static func badgeAccessibilityText(_ dockLabel: String?) -> String? {
        guard let dockLabel = dockLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !dockLabel.isEmpty else { return nil }
        guard Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .commandSwitcher else {
            if let count = Int(dockLabel) { return "Red badge with number \(count)" }
            return "Red badge"
        }
        if Preferences.commandSwitcherBadgeIndicatorOnly { return "Badge indicator" }
        if let count = Int(dockLabel) {
            let threshold = Preferences.commandSwitcherLargeBadgeDigits.threshold
            if count > threshold {
                return Preferences.commandSwitcherLargeBadgeStyle == .plus ? "Badge with more than \(threshold) notifications" : "Badge with many notifications"
            }
            return "Badge with number \(count)"
        }
        return Preferences.commandSwitcherHideNonNumericBadges ? "Badge indicator" : "Badge"
    }

    static func displayIcon(for window: Window) -> CGImage? {
        guard Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .commandSwitcher else { return window.icon }
        return CommandSwitcherIconResolver.displayIcon(for: window.application) ?? window.icon
    }
}
