import Foundation

struct AppVersion {
    let shortVersion: String
    let bundleVersion: String

    var displayVersion: String {
        shortVersion
    }

    var buildDisplay: String? {
        guard bundleVersion != shortVersion else { return nil }
        return bundleVersion
    }

    static let current = AppVersion(bundle: .main)

    init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        let shortVersion = (info["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleVersion = (info["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.shortVersion = shortVersion?.isEmpty == false ? shortVersion! : "0"
        self.bundleVersion = bundleVersion?.isEmpty == false ? bundleVersion! : (shortVersion ?? "0")
    }
}
