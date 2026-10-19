import XCTest
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
    func update(_ kind: LibraryUpdate, story: Story, engine: String, instruction: String,
                localJSON: Bool, delay: TimeInterval, serverURL: URL?) async throws -> LibraryUpdateResult {
        XCTAssertEqual(engine, "None")
        XCTAssertNil(serverURL)
        XCTAssertFalse(localJSON)
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
final class LocalLibraryWorkflowTests: XCTestCase {
    private func config() -> AppConfig { AppConfig(defaults: UserDefaults(suiteName: UUID().uuidString)!) }

    func testTitleOnlySavesAndEnrichesWithoutGenerationMetadata() async throws {
        let repository = LocalLibraryRepository()
        let updater = LocalLibraryUpdaterStub()
        let vm = LibraryViewModel(config: config(), repository: repository, updater: updater)
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
        let vm = LibraryViewModel(config: config(), repository: repository, updater: LocalLibraryUpdaterStub(failSearch: true))
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
        let vm = LibraryViewModel(config: config(), repository: repository, updater: updater)
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
        let vm = LibraryViewModel(config: config(), repository: repository, uploader: LocalUploaderStub())
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
            if url.host == "www.bing.com" {
                XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value, "ISRO mission")
                let rss = "<rss><channel><item><title>ISRO mission</title><link>https://www.bing.com/news/apiclick.aspx?url=https%3A%2F%2Fpublisher.test%2Farticle</link><source>Publisher</source></item></channel></rss>"
                return (200, [:], Data(rss.utf8))
            }
            if url.path == "/article" {
                return (200, [:], Data(#"<meta content='/photo.jpg?a=1&amp;b=2' property='og:image'>"#.utf8))
            }
            XCTAssertEqual(url.host, "publisher.test")
            XCTAssertEqual(url.path, "/photo.jpg")
            XCTAssertEqual(url.query, "a=1&b=2")
            XCTAssertEqual(request.httpMethod, "HEAD")
            return (200, ["Content-Type": "image/jpeg"], Data())
        }
        let client = LocalLibraryUpdateClient(httpClient: http())
        var story = Story(title: "ISRO mission")
        let news = try await client.update(.news, story: story, engine: "None", instruction: "", localJSON: false, delay: 0, serverURL: nil)
        XCTAssertEqual(news.news?.first?.url, "https://publisher.test/article")
        story.sourceLinks = news.news
        let images = try await client.update(.images, story: story, engine: "None", instruction: "", localJSON: false, delay: 0, serverURL: nil)
        XCTAssertEqual(images.images, ["https://publisher.test/photo.jpg?a=1&b=2"])
    }

    func testTagsNeedNoNetworkAndFailedNewsNeverUsesFixtures() async throws {
        LocalLibraryHTTPStub.handler = { _ in XCTFail("Hashtags must not use the network"); throw URLError(.notConnectedToInternet) }
        let client = LocalLibraryUpdateClient(httpClient: http())
        let result = try await client.update(.hashtags, story: Story(title: "ISRO mission and ISRO crew"), engine: "None", instruction: "", localJSON: false, delay: 0, serverURL: nil)
        XCTAssertEqual(result.hashtags, ["#ISRO", "#mission", "#crew"])
        LocalLibraryHTTPStub.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.update(.news, story: Story(title: "ISRO mission"), engine: "None", instruction: "", localJSON: true, delay: 0, serverURL: nil)
            XCTFail("Must fail rather than returning sample news")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Could not find related news")) }
    }

    func testTelegramUsesExistingTokenAndChatCacheForTitleOnlyStory() async throws {
        let home = try temporaryHome()
        let files = FileStore()
        try files.writeCreatingDirectory(Data("# comment\n123:fake-token\n".utf8), to: home.appendingPathComponent("Documents/telegrambot/bot_token.txt"))
        try files.writeCreatingDirectory(Data(#"{"chat_id":42}"#.utf8), to: home.appendingPathComponent(".cache/telegram_bot_chat_id.json"))
        LocalLibraryHTTPStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/bot123:fake-token/sendMessage")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            XCTAssertEqual(body["chat_id"], "42")
            XCTAssertEqual(body["text"], "Only a title\n#News")
            return (200, [:], Data(#"{"ok":true,"result":{"message_id":1}}"#.utf8))
        }
        let result = try await uploader(home: home).upload(Story(title: "Only a title", hashtags: ["#News"]), to: .telegram, options: .init())
        XCTAssertEqual(result.message, "Telegram: sent to 1 chat(s).")
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

    func testTelegramLongUnicodeTextPreservesContentWithinLimits() {
        let text = String(repeating: "📰News ", count: 1800)
        let chunks = LocalStoryUploadClient.textChunks(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 4096 })
    }
}
