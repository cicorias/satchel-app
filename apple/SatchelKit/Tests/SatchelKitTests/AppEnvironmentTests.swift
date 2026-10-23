import Foundation
import Testing

@testable import SatchelKit

@Suite struct AppEnvironmentTests {
    @Test func readsSatchelKeysFromInfoDictionary() throws {
        let env = try AppEnvironment(infoDictionary: [
            "SatchelAppGroup": "group.com.example.satchel",
            "SatchelICloudContainer": "iCloud.com.example.satchel",
            "SatchelCloudKitZone": "Library",
            "CFBundleShortVersionString": "2026.10.0",
            "CFBundleVersion": "1",
        ])
        #expect(env.appGroup == "group.com.example.satchel")
        #expect(env.cloudKitZone == "Library")
        #expect(env.siteURL == nil)
    }

    @Test func readsTheSiteURLWhenPresent() throws {
        let env = try AppEnvironment(infoDictionary: [
            "SatchelAppGroup": "g", "SatchelICloudContainer": "c", "SatchelCloudKitZone": "Library",
            "CFBundleShortVersionString": "2026.10.0", "CFBundleVersion": "1",
            "SatchelSiteURL": "https://example.github.io/satchel-app/",
        ])
        #expect(
            env.siteURL?.appending(path: "privacy.html").absoluteString
                == "https://example.github.io/satchel-app/privacy.html")
    }

    @Test func reportsTheMissingKey() {
        #expect(throws: AppEnvironment.MissingKey(key: "SatchelAppGroup")) {
            try AppEnvironment(infoDictionary: [:])
        }
    }
}
