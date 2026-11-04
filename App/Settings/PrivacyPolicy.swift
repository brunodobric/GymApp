import Foundation

/// Javna pravila privatnosti (GitHub Pages iz mape `site/`), na jeziku sučelja.
enum PrivacyPolicy {
    static var url: URL {
        let isCroatian = Bundle.main.preferredLocalizations.first == "hr"
        return URL(string: isCroatian
            ? "https://brunodobric.github.io/GymApp/privacy/"
            : "https://brunodobric.github.io/GymApp/privacy/en/")!
    }
}
