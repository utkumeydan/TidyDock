import Foundation

/// Looks up a string in the app's Localizable.strings. Keys are the English text.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Looks up a format string and fills it in.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}
