import Foundation

/// In-app language override, independent of System Settings > Language &
/// Region (ported from DKB Monitor). Views use `LocalizedStringKey`
/// everywhere, so overriding `\.locale` on the root views in
/// `KeyCellarApp.swift` is enough to make the switch take effect.
enum AppLocale: String, CaseIterable, Identifiable {
    case en, vi

    var id: Self { self }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Falls back to the system's language exactly once, on first launch,
    /// before the user has picked anything in Settings.
    static var systemDefault: AppLocale {
        Locale.current.language.languageCode?.identifier == "vi" ? .vi : .en
    }

    /// The `.lproj` bundle of the in-app language, for `String(localized:bundle:)`.
    /// `String(localized:)` alone reads the *system* language and ignores the
    /// `\.locale` override the views get (its `locale:` parameter only formats
    /// numbers, it does not pick the table), so anything built as a `String`
    /// (notification text, status messages, validation) goes through this.
    /// Same key as the `@AppStorage("languagePreference")` in Settings.
    static var bundle: Bundle {
        let language = UserDefaults.standard.string(forKey: "languagePreference").flatMap(AppLocale.init(rawValue:)) ?? systemDefault
        return Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}
