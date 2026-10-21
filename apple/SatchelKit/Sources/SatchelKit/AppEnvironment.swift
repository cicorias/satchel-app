import Foundation

/// Identifiers shared by the app and its extensions.
///
/// Values are injected into each target's Info.plist from `config/app.config.json`
/// (via `Config/Generated.xcconfig`), so nothing here hard-codes a bundle ID.
public struct AppEnvironment: Sendable, Equatable {
    public var appGroup: String
    public var iCloudContainer: String
    public var cloudKitZone: String
    public var version: String
    public var build: String

    public init(appGroup: String, iCloudContainer: String, cloudKitZone: String, version: String, build: String) {
        self.appGroup = appGroup
        self.iCloudContainer = iCloudContainer
        self.cloudKitZone = cloudKitZone
        self.version = version
        self.build = build
    }

    /// Reads the `Satchel*` keys from an Info.plist dictionary.
    public init(infoDictionary info: [String: Any]) throws(MissingKey) {
        func value(_ key: String) throws(MissingKey) -> String {
            guard let value = info[key] as? String, !value.isEmpty else { throw MissingKey(key: key) }
            return value
        }
        self.init(
            appGroup: try value("SatchelAppGroup"),
            iCloudContainer: try value("SatchelICloudContainer"),
            cloudKitZone: try value("SatchelCloudKitZone"),
            version: try value("CFBundleShortVersionString"),
            build: try value("CFBundleVersion")
        )
    }

    public static func current(bundle: Bundle = .main) throws(MissingKey) -> AppEnvironment {
        try AppEnvironment(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public struct MissingKey: Error, Equatable {
        public let key: String
    }
}
