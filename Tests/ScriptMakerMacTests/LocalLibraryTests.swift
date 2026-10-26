import XCTest
import NewsSearch
@testable import ScriptMakerMac

private actor LocalLibraryRepository: StoryRepository {
    var stories: [Story] = []
    func save(_ story: Story) { stories.removeAll { $0.id == story.id }; stories.insert(story, at: 0) }
    func all() -> [Story] { stories }
    func remove(id: String) { stories.removeAll { $0.id == id } }
}

private actor LocalLibraryUpdaterStub: LibraryUpdating {
    var titles: [String] = []
    var failSearch = false
    init(failSearch: Bool = false) { self.failSearch = failSearch }
    func update(_ kind: LibraryUpdate, story: Story) async throws -> LibraryUpdateResult {
        titles.append(story.title)
        if kind == .hashtags { return LibraryUpdateResult(hashtags: ["#LocalNews"]) }
        if failSearch { throw APIError.transport("Publisher unavailable") }
        if kind == .news { return LibraryUpdateResult(news: [.init(title: story.title, url: "https://publisher.test/article", source: "Publisher")]) }
        return LibraryUpdateResult(images: ["https://publisher.test/photo.jpg"])
    }
}

private struct LocalUploaderStub: StoryUploading {
    func upload(_ story: Story, to destination: LibraryUploadDestination, options: LibraryUploadOptions) async throws -> LibraryUploadResult {
        .init(message: "Uploaded", receipt: .init(id: 7, previewURL: "https://drive.google.com/file/d/example/preview", thumbnailURL: "", uploadedAt: "now"))
    }
}

@MainActor
private final class UploadSettingsStub: UploadSettingsStoring {
    var options = LibraryUploadOptions()
    var fails = false
    func load() throws -> LibraryUploadOptions {
        if fails { throw LibraryOperationError.requestFailed("Settings locked") }
        return options
    }
    func save(_ options: LibraryUploadOptions) throws {
        if fails { throw LibraryOperationError.requestFailed("Settings locked") }
        self.options = options
    }
}

private actor CapturingUploader: StoryUploading {
    var received: [LibraryUploadOptions] = []
    func upload(_ story: Story, to destination: LibraryUploadDestination, options: LibraryUploadOptions) async throws -> LibraryUploadResult {
        received.append(options)
        return .init(message: "Uploaded")
    }
}


private actor LibrarySearchProbe: NewsSearching {
    var limits: [Int] = []
    func headlines(category: NewsSearch.NewsCategory, limit: Int) async throws -> [NewsArticle] { [] }
    func search(_ query: String, limit: Int) async throws -> [NewsArticle] {
        limits.append(limit)
        return [NewsArticle(title: query, url: URL(string: "https://publisher.test/article")!, source: "Publisher")]
    }
}

@MainActor
final class LocalLibraryWorkflowTests: XCTestCase {
    private func config() -> AppConfig { AppConfig(store: KeyValueStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)) }

    func testLibraryUsesConfiguredFrameworkAndCurrentResultLimit() async throws {
        let config = config()
        let probe = LibrarySearchProbe()
        let client = LocalLibraryUpdateClient(httpClient: HTTPClient(), news: { (probe, config.newsPageSize) })
        let story = Story(title: "ISRO mission")
        let result = try await client.update(.news, story: story)
        XCTAssertEqual(result.news?.first?.url, "https://publisher.test/article")
        config.newsPageSize = 42
        _ = try await client.update(.news, story: story)
        let limits = await probe.limits
        XCTAssertEqual(limits, [20, 42])
    }

    func testUploadUsesLatestSavedSettingsWithoutAnUploadForm() async throws {
        let settings = UploadSettingsStub()
        let preferences = PreferencesViewModel(config: config(), uploadSettings: settings)
        preferences.loadUploadSettings()
        preferences.uploadOptions = .init(telegramToken: " 123:token ", telegramChatID: " 42 ", includeTelegramGroups: true,
                                          googleAccessToken: " access ", googleEndpoint: "https://script.google.com/macros/s/test/exec")
        preferences.saveUploadSettings()
        XCTAssertNil(preferences.uploadSettingsError)
        XCTAssertNotNil(preferences.uploadSettingsNotice)
        let reopened = PreferencesViewModel(config: config(), uploadSettings: settings)
        reopened.loadUploadSettings()
        XCTAssertEqual(reopened.uploadOptions, settings.options)
        XCTAssertEqual(reopened.uploadOptions.telegramChatID, "42")
        let uploader = CapturingUploader()
        let story = Story(title: "One click")
        let vm = LibraryViewModel( repository: LocalLibraryRepository(), uploader: uploader, uploadSettings: settings)
        vm.stories = [story]
        await vm.upload(story, to: .telegram)
        reopened.uploadOptions.telegramChatID = "84"
        reopened.saveUploadSettings()
        await vm.upload(story, to: .googleSheets)
        let received = await uploader.received
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first?.telegramChatID, "42")
        XCTAssertEqual(received.last, settings.options)
        XCTAssertFalse(vm.isUploading)
    }

    func testUploadSettingsFailuresPreventUploadAndReportSaveFailure() async throws {
        let settings = UploadSettingsStub()
        let preferences = PreferencesViewModel(config: config(), uploadSettings: settings)
        preferences.loadUploadSettings()
        settings.fails = true
        preferences.saveUploadSettings()
        XCTAssertNotNil(preferences.uploadSettingsError)
        XCTAssertNil(preferences.uploadSettingsNotice)
        preferences.loadUploadSettings()
        XCTAssertFalse(preferences.canSaveUploadSettings)
        let uploader = CapturingUploader()
        let vm = LibraryViewModel( repository: LocalLibraryRepository(), uploader: uploader, uploadSettings: settings)
        let story = Story(title: "Blocked")
        vm.stories = [story]
        vm.selectedStoryID = story.id
        await vm.upload(story, to: .telegram)
        let received = await uploader.received
        XCTAssertTrue(received.isEmpty)
        XCTAssertTrue(vm.actionNotice?.contains("Settings locked") == true)
        XCTAssertFalse(vm.isUploading)
    }

    func testInvalidUploadSettingsPreserveSavedValues() throws {
        let settings = UploadSettingsStub()
        settings.options.telegramChatID = "42"
        let preferences = PreferencesViewModel(config: config(), uploadSettings: settings)
        preferences.loadUploadSettings()
        preferences.uploadOptions.telegramChatID = "invalid"
        preferences.saveUploadSettings()
        XCTAssertEqual(settings.options.telegramChatID, "42")
        XCTAssertNotNil(preferences.uploadSettingsError)
        preferences.uploadOptions.telegramChatID = "84"
        preferences.uploadOptions.googleEndpoint = "https://example.com/upload"
        preferences.saveUploadSettings()
        XCTAssertEqual(settings.options.telegramChatID, "42")
        XCTAssertNotNil(preferences.uploadSettingsError)
    }

    func testTitleOnlySavesAndEnrichesWithoutGenerationMetadata() async throws {
        let repository = LocalLibraryRepository()
        let updater = LocalLibraryUpdaterStub()
        let vm = LibraryViewModel( repository: repository, updater: updater)
        vm.newStoryTitle = "   Local news headline   "
        XCTAssertTrue(vm.canAddStory)
        let added = await vm.addStory()
        XCTAssertTrue(added)
        let story = try XCTUnwrap(vm.selectedStory)
        XCTAssertEqual(story.title, "Local news headline")
        XCTAssertNil(story.scriptText)
        XCTAssertNil(story.stageOutputs)
        XCTAssertNil(story.videoURL)
        XCTAssertEqual(story.hashtags, ["#LocalNews"])
        XCTAssertEqual(story.sourceLinks?.first?.source, "Publisher")
        XCTAssertEqual(story.imageURLs, ["https://publisher.test/photo.jpg"])
        let persisted = await repository.all()
        XCTAssertEqual(persisted, [story])
    }

    func testBlankTitleRejectedAndFailedSearchKeepsSavedTitleAndTags() async throws {
        let repository = LocalLibraryRepository()
        let vm = LibraryViewModel( repository: repository, updater: LocalLibraryUpdaterStub(failSearch: true))
        vm.newStoryTitle = " \n "
        XCTAssertFalse(vm.canAddStory)
        let rejected = await vm.addStory()
        XCTAssertFalse(rejected)
        vm.newStoryTitle = "News headline"
        let added = await vm.addStory()
        XCTAssertTrue(added)
        XCTAssertEqual(vm.stories.count, 1)
        XCTAssertEqual(vm.selectedStory?.hashtags, ["#LocalNews"])
        XCTAssertNil(vm.selectedStory?.sourceLinks)
        XCTAssertTrue(vm.actionNotice?.contains("Publisher unavailable") == true)
        XCTAssertFalse(vm.isAddingStory)
        XCTAssertTrue(vm.busyUpdates.isEmpty)
        await vm.refresh()
        XCTAssertEqual(vm.stories.count, 1)
        XCTAssertNil(vm.notice)
    }

    func testEditedTitleResearchesNewHeadlineAndPreservesOriginalAndImportedImages() async throws {
        let repository = LocalLibraryRepository()
        let updater = LocalLibraryUpdaterStub()
        let original = Story(title: "Old title", imageURLs: ["file:///tmp/imported.jpg", "https://old.test/old.jpg"])
        await repository.save(original)
        let vm = LibraryViewModel( repository: repository, updater: updater)
        await vm.refresh()
        vm.prepareEdits(original)
        vm.editedTitle = "New headline"
        XCTAssertTrue(vm.canSaveEdits)
        let saved = await vm.saveEdits(id: original.id)
        XCTAssertTrue(saved)
        XCTAssertEqual(vm.stories.first(where: { $0.id == original.id }), original)
        let edited = try XCTUnwrap(vm.selectedStory)
        XCTAssertNotEqual(edited.id, original.id)
        XCTAssertEqual(edited.headline, "New headline")
        XCTAssertNil(edited.scriptText)
        XCTAssertEqual(edited.imageURLs, ["file:///tmp/imported.jpg", "https://publisher.test/photo.jpg"])
        let titles = await updater.titles
        XCTAssertEqual(titles, Array(repeating: "New headline", count: 3))
    }

    func testUploadReceiptPersistsOnOriginalStory() async throws {
        let repository = LocalLibraryRepository()
        let story = Story(title: "Upload target")
        await repository.save(story)
        let vm = LibraryViewModel( repository: repository, uploader: LocalUploaderStub())
        await vm.refresh()
        await vm.upload(story, to: .googleSheets)
        XCTAssertEqual(vm.selectedStory?.uploadReceipt?.id, 7)
        XCTAssertEqual(vm.actionNotice, "Uploaded")
        XCTAssertFalse(vm.isUploading)
        await vm.refresh()
        XCTAssertEqual(vm.selectedStory?.uploadReceipt?.id, 7)
    }
}

private final class LocalLibraryHTTPStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                captured.httpBody = data
            }
            let (status, headers, data) = try Self.handler!(captured)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class LocalLibraryNetworkTests: XCTestCase {
    override func tearDown() { LocalLibraryHTTPStub.handler = nil; super.tearDown() }
    private func http() -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalLibraryHTTPStub.self]
        return HTTPClient(session: URLSession(configuration: configuration))
    }
    private func updater() -> LocalLibraryUpdateClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalLibraryHTTPStub.self]
        let session = URLSession(configuration: configuration)
        let client = NewsSearchClient(configuration: NewsSearchConfiguration(cacheDuration: 0),
                                      transport: URLSessionNewsTransport(session: session), cache: NewsSearchCache())
        return LocalLibraryUpdateClient(httpClient: HTTPClient(session: session), news: { (client, 20) })
    }
    private func uploader(home: URL, token: String? = nil) -> LocalStoryUploadClient {
        LocalStoryUploadClient(httpClient: http(), googleHTTPClient: http(), files: FileStore(), home: home, environmentToken: { token })
    }
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testDirectSearchUnwrapsPublisherURLAndChecksArticleImage() async throws {
        LocalLibraryHTTPStub.handler = { request in
            let url = request.url!
            if url.host == "news.google.com" {
                XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value, "ISRO mission when:24h")
                let rss = "<rss><channel><item><title>ISRO mission</title><link>https://www.bing.com/news/apiclick.aspx?url=https%3A%2F%2Fpublisher.test%2Farticle</link><source>Publisher</source></item></channel></rss>"
                return (200, [:], Data(rss.utf8))
            }
            if url.path == "/article" {
                return (200, [:], Data(#"<meta content='/photo.jpg?a=1&amp;b=2' property='og:image'>"#.utf8))
            }
            XCTAssertEqual(url.host, "publisher.test")
            XCTAssertEqual(url.path, "/photo.jpg")
            XCTAssertEqual(url.query, "a=1&b=2")
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, ["Content-Type": "image/jpeg"], Data([1]))
        }
        let client = updater()
        var story = Story(title: "ISRO mission")
        let news = try await client.update(.news, story: story)
        XCTAssertEqual(news.news?.first?.url, "https://publisher.test/article")
        story.sourceLinks = news.news
        let images = try await client.update(.images, story: story)
        XCTAssertEqual(images.images, ["https://publisher.test/photo.jpg?a=1&b=2"])
    }

    func testTagsNeedNoNetworkAndFailedNewsNeverUsesFixtures() async throws {
        LocalLibraryHTTPStub.handler = { _ in XCTFail("Hashtags must not use the network"); throw URLError(.notConnectedToInternet) }
        let client = updater()
        let result = try await client.update(.hashtags, story: Story(title: "ISRO mission and ISRO crew"))
        XCTAssertEqual(result.hashtags, ["#ISRO", "#mission", "#crew"])
        LocalLibraryHTTPStub.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.update(.news, story: Story(title: "ISRO mission"))
            XCTFail("Must fail rather than returning sample news")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Could not find related news")) }
    }

    func testTelegramUsesSavedTokenAndAppSupportChatCacheForTitleOnlyStory() async throws {
        let home = try temporaryHome()
        let files = FileStore()
        try files.writeCreatingDirectory(Data(#"{"chat_id":42}"#.utf8), to: home.appendingPathComponent("Library/Application Support/ScriptMakerMac/telegram-chat.json"))
        LocalLibraryHTTPStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/bot123:fake-token/sendMessage")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            XCTAssertEqual(body["chat_id"], "42")
            XCTAssertEqual(body["text"], "Only a title\n#News")
            return (200, [:], Data(#"{"ok":true,"result":{"message_id":1}}"#.utf8))
        }
        let result = try await uploader(home: home).upload(Story(title: "Only a title", hashtags: ["#News"]), to: .telegram, options: .init(telegramToken: "123:fake-token"))
        XCTAssertEqual(result.message, "Telegram: sent to 1 chat(s).")
    }

    func testLegacyDocumentsTokenIsNotUsedImplicitly() async throws {
        let home = try temporaryHome()
        try FileStore().writeCreatingDirectory(Data("123:old-token".utf8), to: home.appendingPathComponent("Documents/telegrambot/bot_token.txt"))
        LocalLibraryHTTPStub.handler = { _ in
            XCTFail("Missing saved credentials must fail before networking")
            return (500, [:], Data())
        }
        do {
            _ = try await uploader(home: home).upload(Story(title: "Test"), to: .telegram, options: .init())
            XCTFail("Expected Settings guidance")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Settings"))
        }
    }

    func testSavedTelegramSettingsOverrideExistingFiles() async throws {
        let home = try temporaryHome()
        try FileStore().writeCreatingDirectory(Data("123:old-token".utf8), to: home.appendingPathComponent("Documents/telegrambot/bot_token.txt"))
        LocalLibraryHTTPStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/bot456:saved-token/sendMessage")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            XCTAssertEqual(body["chat_id"], "84")
            return (200, [:], Data(#"{"ok":true,"result":{}}"#.utf8))
        }
        _ = try await uploader(home: home).upload(Story(title: "Saved settings"), to: .telegram,
            options: .init(telegramToken: "456:saved-token", telegramChatID: "84"))
    }

    func testSavedGoogleSettingsOverrideEnvironmentAndClasp() async throws {
        let home = try temporaryHome()
        let video = home.appendingPathComponent("reel.mp4")
        try Data([1]).write(to: video)
        try Data("invalid old login".utf8).write(to: home.appendingPathComponent(".clasprc.json"))
        LocalLibraryHTTPStub.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://script.google.com/macros/s/saved/exec")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer saved-access")
            return (200, [:], Data(#"{"status":"success","id":2,"previewUrl":"https://drive.google.com/preview","timestamp":"now"}"#.utf8))
        }
        _ = try await uploader(home: home, token: "old-access").upload(Story(title: "Saved settings", videoURL: video.absoluteString), to: .googleSheets,
            options: .init(googleAccessToken: "saved-access", googleEndpoint: "https://script.google.com/macros/s/saved/exec"))
    }

    func testTelegramSurfacesRejectedSendAndNeverLeaksToken() async throws {
        LocalLibraryHTTPStub.handler = { _ in throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "secret-token"]) }
        let result = try await uploader(home: temporaryHome()).upload(Story(title: "Only title"), to: .telegram,
            options: .init(telegramToken: "123:secret-token", telegramChatID: "42"))
        XCTAssertTrue(result.message.contains("Partial failure"))
        XCTAssertFalse(result.message.contains("secret-token"))
    }

    func testGoogleContractAndRedirectDropsBodyAndAuthorization() async throws {
        let home = try temporaryHome()
        let video = home.appendingPathComponent("reel.mp4")
        try Data([1, 2, 3]).write(to: video)
        LocalLibraryHTTPStub.handler = { request in
            if request.url?.host == "script.google.com" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
                XCTAssertEqual(body["title"], "Test upload")
                XCTAssertEqual(body["base64Video"], "AQID")
                XCTAssertEqual(body["mimeType"], "video/mp4")
                XCTAssertNil(body["script"])
                return (302, ["Location": "https://script.googleusercontent.com/receipt"], Data())
            }
            XCTAssertEqual(request.url?.absoluteString, "https://script.googleusercontent.com/receipt")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, [:], Data(#"{"status":"success","id":11,"previewUrl":"https://drive.google.com/preview","timestamp":"now"}"#.utf8))
        }
        let result = try await uploader(home: home, token: "test-access").upload(Story(title: "Test upload", videoURL: video.absoluteString), to: .googleSheets, options: .init())
        XCTAssertEqual(result.receipt?.id, 11)
    }

    func testGoogleVideoRequiredOnlyForGoogleUpload() async throws {
        LocalLibraryHTTPStub.handler = { _ in XCTFail("Missing video must fail before any request"); throw URLError(.badURL) }
        do {
            _ = try await uploader(home: temporaryHome()).upload(Story(title: "Title only"), to: .googleSheets, options: .init())
            XCTFail("Endpoint requires video")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Attach a video")) }
    }

    func testTelegramLongUnicodeTextPreservesContentWithinLimits() throws {
        let text = String(repeating: "📰News ", count: 1800)
        let chunks = LocalStoryUploadClient.textChunks(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 4096 })
    }

    func testHashtagsPreserveHindiMarksAndShortNames() throws {
        XCTAssertEqual(LocalLibraryUpdateClient.hashtags(for: "दिल्ली में AI मिशन"), ["#दिल्ली", "#में", "#AI", "#मिशन"])
    }

    func testGoogleRefreshesExistingClaspLoginBeforeUpload() async throws {
        let home = try temporaryHome()
        let video = home.appendingPathComponent("reel.mp4")
        try Data([1]).write(to: video)
        try Data(#"{"tokens":{"default":{"client_id":"test-client","client_secret":"test-secret","refresh_token":"refresh+value"}}}"#.utf8).write(to: home.appendingPathComponent(".clasprc.json"))
        LocalLibraryHTTPStub.handler = { request in
            if request.url?.host == "oauth2.googleapis.com" {
                XCTAssertEqual(request.httpMethod, "POST")
                let body = String(decoding: request.httpBody!, as: UTF8.self)
                XCTAssertTrue(body.contains("refresh_token=refresh%2Bvalue"))
                XCTAssertTrue(body.contains("grant_type=refresh_token"))
                return (200, [:], Data(#"{"access_token":"refreshed-access"}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-access")
            return (200, [:], Data(#"{"status":"success","id":2,"previewUrl":"https://drive.google.com/preview","timestamp":"now"}"#.utf8))
        }
        let result = try await uploader(home: home).upload(Story(title: "Headline", videoURL: video.absoluteString), to: .googleSheets, options: .init())
        XCTAssertEqual(result.receipt?.id, 2)
    }

    func testTelegramGroupFailureReportsSuccessfulDirectDelivery() async throws {
        let home = try temporaryHome()
        try FileStore().writeCreatingDirectory(Data("[-1001]".utf8), to: home.appendingPathComponent("Library/Application Support/ScriptMakerMac/telegram-groups.json"))
        LocalLibraryHTTPStub.handler = { request in
            if request.url?.lastPathComponent == "getUpdates" {
                return (200, [:], Data(#"{"ok":true,"result":[]}"#.utf8))
            }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            if body["chat_id"] == "42" { return (200, [:], Data(#"{"ok":true,"result":{}}"#.utf8)) }
            XCTAssertEqual(body["chat_id"], "-1001")
            return (403, [:], Data(#"{"ok":false,"description":"Forbidden"}"#.utf8))
        }
        let result = try await uploader(home: home).upload(Story(title: "Title only"), to: .telegram,
            options: .init(telegramToken: "123:fake", telegramChatID: "42", includeTelegramGroups: true))
        XCTAssertTrue(result.message.contains("sent to 1 chat(s)"))
        XCTAssertTrue(result.message.contains("Partial failure"))
        XCTAssertTrue(result.message.contains("-1001"))
    }
}

@MainActor
final class LibraryImageAppendTests: XCTestCase {
    func testRepeatedImageFetchPreservesExistingImagesAndDeduplicatesNewResults() async throws {
        let repository = LocalLibraryRepository()
        let story = Story(title: "Image test", imageURLs: ["file:///tmp/imported.jpg", "https://existing.test/photo.jpg"])
        await repository.save(story)
        let vm = LibraryViewModel( repository: repository, updater: LocalLibraryUpdaterStub())
        await vm.refresh()
        vm.selectedStoryID = story.id
        await vm.update(.images)
        await vm.update(.images)
        XCTAssertEqual(vm.selectedStory?.imageURLs, ["file:///tmp/imported.jpg", "https://existing.test/photo.jpg", "https://publisher.test/photo.jpg"])
    }
}

extension LocalLibraryNetworkTests {
    func testGoogleWrapperUsesPublisherSearchAndTriesAlternativeImageMetadata() async throws {
        let probe = LibrarySearchProbe()
        LocalLibraryHTTPStub.handler = { request in
            switch request.url!.path {
            case "/article":
                return (200, [:], Data(#"<meta property="og:image" content="/broken.jpg"><meta name="twitter:image" content="/usable.jpg">"#.utf8))
            case "/broken.jpg": return (403, [:], Data())
            case "/usable.jpg":
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://publisher.test/article")
                return (200, ["Content-Type": "image/jpeg"], Data([1, 2, 3]))
            default:
                XCTFail("Google wrapper should not be scraped for publisher images")
                return (404, [:], Data())
            }
        }
        let client = LocalLibraryUpdateClient(httpClient: http(), news: { (probe, 20) }, imageNews: { (probe, 20) })
        let story = Story(title: "Indian physicist wins Oskar Klein medal, one of the top prizes in physics", sourceLinks: [.init(title: "News", url: "https://news.google.com/rss/articles/opaque", source: "Publisher")])
        let result = try await client.update(.images, story: story)
        XCTAssertEqual(result.images, ["https://publisher.test/usable.jpg"])
        XCTAssertEqual(result.imagePreviews?["https://publisher.test/usable.jpg"], Data([1, 2, 3]))
    }

    func testFetchMoreSkipsAlreadySavedImageAndReturnsAnotherCandidate() async throws {
        let probe = LibrarySearchProbe()
        LocalLibraryHTTPStub.handler = { request in
            if request.url!.path == "/article" {
                return (200, [:], Data(#"<meta property="og:image" content="/old.jpg"><meta name="twitter:image" content="/new.jpg">"#.utf8))
            }
            XCTAssertEqual(request.url!.path, "/new.jpg")
            return (200, ["Content-Type": "image/jpeg"], Data([4]))
        }
        let client = LocalLibraryUpdateClient(httpClient: http(), news: { (probe, 20) })
        let story = Story(title: "Physics", imageURLs: ["https://publisher.test/old.jpg"])
        let result = try await client.update(.images, story: story)
        XCTAssertEqual(result.images, ["https://publisher.test/new.jpg"])
    }
}
