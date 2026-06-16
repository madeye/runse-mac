import Foundation

/// Anchor class used to resolve the RunseCore framework bundle at runtime so
/// `String(localized:bundle:)` reads the framework's own string catalog
/// instead of the host app's.
private final class RunseCoreBundleToken {}

extension Bundle {
    /// The RunseCore framework bundle (where `Localizable.xcstrings` lives).
    static let runseCore = Bundle(for: RunseCoreBundleToken.self)
}

public enum RunseConstants {
    public static let appGroupID = "group.io.github.madeye.runse"
    public static let keychainAccessGroup = "io.github.madeye.runse.shared"
    public static let defaultProfileID = "nvidia-kimi-k2-6"
    public static let defaultTranslationLanguage = "English"
    public static let yearlySubscriptionProductID = "io.github.madeye.runse.pro.yearly"
}
