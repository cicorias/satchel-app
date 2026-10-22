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
    }

    @Test func reportsTheMissingKey() {
        #expect(throws: AppEnvironment.MissingKey(key: "SatchelAppGroup")) {
            try AppEnvironment(infoDictionary: [:])
        }
    }
}
