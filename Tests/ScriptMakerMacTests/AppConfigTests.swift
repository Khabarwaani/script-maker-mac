import XCTest
@testable import ScriptMakerMac

final class AppConfigTests: XCTestCase {
    @MainActor
    func testNewsSettingsPersistAndInvalidEditsPreserveSavedSettings() throws {
        let defaults = makeIsolatedDefaults()
        let config = AppConfig(store: KeyValueStore(defaults: defaults))
        XCTAssertEqual(config.newsSettings, NewsDiscoverySettings())
        let vm = PreferencesViewModel(config: config)
        vm.newsSearchHours = 12
        vm.newsCacheHours = 2
        vm.draftNewsSettings.providerOrder = .bingThenGoogle
        vm.newsRegionGeoText = " United States "
        vm.draftNewsSettings.language = " HI "
        vm.newsPageSize = 75
        XCTAssertEqual(config.newsPageSize, 20)
        vm.saveNewsSettings()
        XCTAssertNil(vm.newsSettingsError)
        XCTAssertNotNil(vm.newsSettingsNotice)
        let reopened = AppConfig(store: KeyValueStore(defaults: defaults))
        XCTAssertEqual(reopened.newsSettings, config.newsSettings)
        XCTAssertEqual(reopened.newsSettings.searchDuration, 12 * 3600)
        XCTAssertEqual(reopened.newsSettings.cacheDuration, 2 * 3600)
        XCTAssertEqual(reopened.newsSettings.region, "US")
        XCTAssertEqual(reopened.newsSettings.language, "hi")
        XCTAssertEqual(reopened.newsSettings.location, "United States")
        XCTAssertEqual(reopened.newsPageSize, 75)
        let saved = config.newsSettings

        // Rejection of city or state
        vm.loadNewsSettings()
        vm.newsRegionGeoText = "Mumbai"
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        XCTAssertTrue(vm.newsSettingsError?.contains("Cities and states are not supported") == true)
        XCTAssertEqual(config.newsSettings, saved)

        // Rejection of another city / state
        vm.loadNewsSettings()
        vm.newsRegionGeoText = "California"
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        XCTAssertEqual(config.newsSettings, saved)

        vm.loadNewsSettings()
        vm.newsPageSize = 100
        vm.newsCacheHours = -1
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        XCTAssertNil(vm.newsSettingsNotice)
        XCTAssertEqual(config.newsSettings, saved)
        XCTAssertEqual(config.newsPageSize, 75)
        vm.loadNewsSettings()
        vm.draftNewsSettings.region = "invalid"
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        XCTAssertEqual(config.newsSettings, saved)
        vm.loadNewsSettings()
        vm.draftNewsSettings.language = ""
        vm.saveNewsSettings()
        XCTAssertNotNil(vm.newsSettingsError)
        config.resetToDefaults()
        XCTAssertEqual(config.newsSettings, NewsDiscoverySettings())
    }

    func testScriptRefinementExecutionModeDefaultsAndPersistence() throws {
        let defaults = makeIsolatedDefaults()
        let config = AppConfig(store: KeyValueStore(defaults: defaults))
        XCTAssertEqual(config.scriptRefinementMode, .fastClean)

        config.scriptRefinementMode = .strictEphemeral
        let reopened = AppConfig(store: KeyValueStore(defaults: defaults))
        XCTAssertEqual(reopened.scriptRefinementMode, .strictEphemeral)

        config.resetToDefaults()
        XCTAssertEqual(config.scriptRefinementMode, .fastClean)
    }










    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "test.suite.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }




    func testNewsPageSizeDefaultAndPersistence() throws {
        let defaults = makeIsolatedDefaults()
        let config = AppConfig(store: KeyValueStore(defaults: defaults))
        XCTAssertEqual(config.newsPageSize, 20)
        config.newsPageSize = 35
        XCTAssertEqual(config.newsPageSize, 35)
        config.resetToDefaults()
        XCTAssertEqual(config.newsPageSize, 20)
    }

    func testAPIErrorLocalization() throws {
        let err = APIError.unreachable(url: "http://localhost:8000", detail: "The request timed out.")
        XCTAssertEqual(err.errorDescription, "Could Not Connect to Server")
        XCTAssertEqual(err.failureReason, "The request timed out.")
    }


    func testRegionGeoResolutionAndValidation() throws {
        // Country codes
        let inGeo = try XCTUnwrap(RegionGeo.resolve("IN"))
        XCTAssertEqual(inGeo.code, "IN")
        XCTAssertEqual(inGeo.name, "India")
        XCTAssertEqual(inGeo.flag, "🇮🇳")

        let usGeo = try XCTUnwrap(RegionGeo.resolve("us"))
        XCTAssertEqual(usGeo.code, "US")
        XCTAssertEqual(usGeo.name, "United States")
        XCTAssertEqual(usGeo.flag, "🇺🇸")

        // Country names
        let canadaGeo = try XCTUnwrap(RegionGeo.resolve("Canada"))
        XCTAssertEqual(canadaGeo.code, "CA")
        XCTAssertEqual(canadaGeo.name, "Canada")

        // Aliases
        let ukGeo = try XCTUnwrap(RegionGeo.resolve("UK"))
        XCTAssertEqual(ukGeo.code, "GB")
        XCTAssertEqual(ukGeo.name, "United Kingdom")

        let usaGeo = try XCTUnwrap(RegionGeo.resolve("USA"))
        XCTAssertEqual(usaGeo.code, "US")

        let uaeGeo = try XCTUnwrap(RegionGeo.resolve("UAE"))
        XCTAssertEqual(uaeGeo.code, "AE")

        // Cities and states must NOT be accepted
        XCTAssertNil(RegionGeo.resolve("Mumbai"))
        XCTAssertNil(RegionGeo.resolve("Delhi"))
        XCTAssertNil(RegionGeo.resolve("Bengaluru"))
        XCTAssertNil(RegionGeo.resolve("California"))
        XCTAssertNil(RegionGeo.resolve("Texas"))
        XCTAssertNil(RegionGeo.resolve("London"))
        XCTAssertNil(RegionGeo.resolve("Tokyo"))
        XCTAssertNil(RegionGeo.resolve("   "))
        XCTAssertNil(RegionGeo.resolve(""))
    }
}
