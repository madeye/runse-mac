import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = UserDefaults(suiteName: RunseConstants.appGroupID) ?? .standard) {
        self.defaults = defaults
    }

    public var defaultTranslationLanguage: String {
        get { defaults.string(forKey: "defaultTranslationLanguage") ?? RunseConstants.defaultTranslationLanguage }
        set { defaults.set(newValue, forKey: "defaultTranslationLanguage") }
    }

    public var hasSeenGetStartedGuide: Bool {
        get { defaults.bool(forKey: "hasSeenGetStartedGuide") }
        set { defaults.set(newValue, forKey: "hasSeenGetStartedGuide") }
    }

    public var isSubscriptionActive: Bool {
        get { defaults.bool(forKey: "isSubscriptionActive") }
        set { defaults.set(newValue, forKey: "isSubscriptionActive") }
    }

    /// Whether the current Apple ID can still redeem the Runse Pro
    /// introductory offer. Written by the main app's `SubscriptionStore`
    /// after each StoreKit refresh, read by the extensions' paywall row so
    /// they advertise the matching price line. Defaults to `true` so brand
    /// new installs (where the main app hasn't run yet) still show the
    /// "first month free" copy that's true for the vast majority of users.
    /// Master switch for the floating selection action bar (PopClip-style
    /// popover). Honored by `SelectionPopoverController` in the macOS app —
    /// off detaches AX observers entirely. Defaults to true; users who find
    /// it intrusive can disable it from the Settings screen.
    public var selectionPopoverEnabled: Bool {
        get {
            if defaults.object(forKey: "selectionPopoverEnabled") == nil { return true }
            return defaults.bool(forKey: "selectionPopoverEnabled")
        }
        set { defaults.set(newValue, forKey: "selectionPopoverEnabled") }
    }

    public var isEligibleForIntroOffer: Bool {
        get {
            // `bool(forKey:)` returns false for missing keys, so probe via
            // `object(forKey:)` to distinguish "never written" from
            // "explicitly false" and apply the optimistic default.
            if defaults.object(forKey: "isEligibleForIntroOffer") == nil { return true }
            return defaults.bool(forKey: "isEligibleForIntroOffer")
        }
        set { defaults.set(newValue, forKey: "isEligibleForIntroOffer") }
    }
}
