import Foundation

/// Ports ScriptMaker's Telegram and Kops flows; no ScriptMakerServer requests.
struct LocalStoryUploadClient: StoryUploading {
    let httpClient: HTTPClient
    let googleHTTPClient: HTTPClient
    let files: FileStore
    let home: URL
    let environmentToken: @Sendable () -> String?

    static let googleEndpoint = "https://script.google.com/macros/s/AKfycbw7W1jqPNn5lR-G2BRKajImt4qEbiZxi6JbUETJ68xqSNnFsH28Qll2GdJW9a1hJjLU/exec"

    func upload(_ story: Story, to destination: LibraryUploadDestination, options: LibraryUploadOptions) async throws -> LibraryUploadResult {
        guard !story.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryOperationError.invalidInput("A title is required for upload.") }
        switch destination {
        case .telegram: return try await telegram(story, options: options)
        case .googleSheets: return try await google(story, options: options)
        }
    }

    static func textChunks(_ text: String, limit: Int = 4096) -> [String] {
        // Telegram counts UTF-16 units; never split an extended grapheme cluster.
        var chunks: [String] = []
        var current = ""
        var length = 0
        for character in text {
            let size = String(character).utf16.count
            if length + size > limit, !current.isEmpty {
                chunks.append(current); current = ""; length = 0
            }
            current.append(character)
            length += size
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func readOptional(_ path: String) throws -> Data? {
        let url = home.appendingPathComponent(path)
        return files.exists(at: url) ? try files.contents(of: url) : nil
    }

    private func lines(_ data: Data?) -> [String] {
        guard let data else { return [] }
        return String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func telegram(_ story: Story, options: LibraryUploadOptions) async throws -> LibraryUploadResult {
        let fileToken = lines(try readOptional("Documents/telegrambot/bot_token.txt")).first ?? ""
        let token = fileToken.isEmpty ? options.telegramToken.trimmingCharacters(in: .whitespacesAndNewlines) : fileToken
        guard !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || ":_-".contains($0) }) else {
            throw LibraryOperationError.invalidInput("Set up Telegram: put your BotFather token in ~/Documents/telegrambot/bot_token.txt, or enter it in the upload sheet.")
        }
        var chatID = options.telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines)
        if chatID.isEmpty, let data = try readOptional(".cache/telegram_bot_chat_id.json") {
            guard let cached = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LibraryOperationError.invalidInput("Could not read cached Telegram chat ID. Enter a chat ID in the upload sheet.")
            }
            if let number = cached["chat_id"] as? NSNumber { chatID = number.stringValue }
            else { chatID = cached["chat_id"] as? String ?? "" }
        }
        var updates: [[String: Any]] = []
        if chatID.isEmpty || options.includeTelegramGroups {
            let result = try await telegramAPI("getUpdates", token: token, fields: ["timeout": 0, "limit": 100])
            updates = result as? [[String: Any]] ?? []
        }
        if chatID.isEmpty {
            let chats = updates.reversed().compactMap { update -> [String: Any]? in
                ((update["message"] ?? update["channel_post"]) as? [String: Any])?["chat"] as? [String: Any]
            }
            guard let chat = chats.first(where: { $0["type"] as? String == "private" }), let id = chat["id"] as? NSNumber else {
                throw LibraryOperationError.invalidInput("Open your bot in Telegram and tap Start, or enter the destination chat ID.")
            }
            chatID = id.stringValue
            let data = try JSONSerialization.data(withJSONObject: ["chat_id": id])
            try files.writeCreatingDirectory(data, to: home.appendingPathComponent(".cache/telegram_bot_chat_id.json"))
        }
        guard Int64(chatID) != nil else { throw LibraryOperationError.invalidInput("Telegram chat ID must be a number.") }
        var targets = [chatID]
        if options.includeTelegramGroups {
            var groups: Set<String> = []
            for line in lines(try readOptional("Documents/telegrambot/group_ids.txt")) {
                guard Int64(line) != nil else { throw LibraryOperationError.invalidInput("Invalid chat ID in ~/Documents/telegrambot/group_ids.txt.") }
                groups.insert(line)
            }
            if let data = try readOptional(".cache/telegram_bot_groups.json") {
                guard let cached = try? JSONDecoder().decode([Int64].self, from: data) else {
                    throw LibraryOperationError.invalidInput("Could not read ~/.cache/telegram_bot_groups.json.")
                }
                groups.formUnion(cached.map(String.init))
            }
            for update in updates {
                for key in ["message", "my_chat_member"] {
                    guard let message = update[key] as? [String: Any], let chat = message["chat"] as? [String: Any],
                          ["group", "supergroup"].contains(chat["type"] as? String ?? ""), let id = chat["id"] as? NSNumber else { continue }
                    let status = (message["new_chat_member"] as? [String: Any])?["status"] as? String ?? ""
                    if ["left", "kicked"].contains(status) { groups.remove(id.stringValue) } else { groups.insert(id.stringValue) }
                }
            }
            let data = try JSONEncoder().encode(groups.compactMap(Int64.init).sorted())
            try files.writeCreatingDirectory(data, to: home.appendingPathComponent(".cache/telegram_bot_groups.json"))
            targets += groups.filter { $0 != chatID }.sorted()
        }
        let caption = ([story.title] + ((story.hashtags ?? []).isEmpty ? [] : [(story.hashtags ?? []).joined(separator: " ")])).joined(separator: "\n")
        let links = (story.sourceLinks ?? []).filter { $0.webURL != nil }.map { "\($0.source): \($0.url)" }.joined(separator: "\n")
        let video: (Data, String)?
        if let value = story.videoURL, !value.isEmpty {
            let url = try localVideoURL(value)
            let data = try files.contents(of: url)
            guard !data.isEmpty, data.count <= 50 * 1024 * 1024 else { throw LibraryOperationError.invalidInput("Telegram video must be nonempty and at most 50 MB.") }
            video = (data, url.lastPathComponent)
        } else { video = nil }
        var completed = 0
        var failures: [String] = []
        for target in targets {
            var sent = 0
            do {
                try Task.checkCancellation()
                if let (data, filename) = video {
                    let shortCaption = caption.utf16.count <= 1024 ? caption : ""
                    try await telegramVideo(token: token, chatID: target, caption: shortCaption, data: data, filename: filename)
                    sent += 1
                    if shortCaption.isEmpty { sent += try await telegramText(caption, token: token, chatID: target) }
                } else { sent += try await telegramText(caption, token: token, chatID: target) }
                if !links.isEmpty { sent += try await telegramText(links, token: token, chatID: target) }
                completed += 1
            } catch is CancellationError { throw CancellationError() }
            catch { failures.append("\(target): delivery incomplete; some messages may already be delivered. \(error.localizedDescription)") }
        }
        return LibraryUploadResult(message: "Telegram: sent to \(completed) chat(s)." + (failures.isEmpty ? "" : " Partial failure; retry may resend delivered messages. " + failures.joined(separator: " ")))
    }

    private func telegramText(_ text: String, token: String, chatID: String) async throws -> Int {
        var count = 0
        for chunk in Self.textChunks(text) {
            _ = try await telegramAPI("sendMessage", token: token, fields: ["chat_id": chatID, "text": chunk])
            count += 1
        }
        return count
    }

    private func telegramAPI(_ method: String, token: String, fields: [String: Any]) async throws -> Any {
        var request = URLRequest(url: URL(string: "https://api.telegram.org/bot\(token)/\(method)")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return try await telegramResponse(request)
    }

    private func telegramVideo(token: String, chatID: String, caption: String, data: Data, filename: String) async throws {
        let boundary = UUID().uuidString
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in ["chat_id": chatID, "caption": caption, "supports_streaming": "true"] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        let safeName = filename.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"video\"; filename=\"\(safeName)\"\r\nContent-Type: \(Self.mimeType(filename))\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: URL(string: "https://api.telegram.org/bot\(token)/sendVideo")!, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await telegramResponse(request)
    }

    private func telegramResponse(_ request: URLRequest) async throws -> Any {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await httpClient.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw LibraryOperationError.requestFailed("Could not reach Telegram. Check your connection.") }
        guard let http = response as? HTTPURLResponse,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LibraryOperationError.invalidInput("Telegram returned an unreadable response.") }
        guard (200..<300).contains(http.statusCode), object["ok"] as? Bool == true else {
            // The request URL contains the bot token; never expose transport diagnostics.
            throw LibraryOperationError.requestFailed("Telegram rejected the request (HTTP \(http.statusCode)). Check the bot token, chat ID and posting permissions.")
        }
        return object["result"] ?? NSNull()
    }

    private func google(_ story: Story, options: LibraryUploadOptions) async throws -> LibraryUploadResult {
        guard let value = story.videoURL, !value.isEmpty else { throw LibraryOperationError.invalidInput("Attach a video before uploading to Google Drive / Sheets.") }
        let video = try localVideoURL(value)
        let raw = try files.contents(of: video)
        guard !raw.isEmpty else { throw LibraryOperationError.invalidInput("The video file is empty.") }
        let endpoint = options.googleEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint.isEmpty ? Self.googleEndpoint : endpoint), url.scheme == "https", url.host == "script.google.com" else {
            throw LibraryOperationError.invalidInput("Google upload needs an HTTPS script.google.com deployment URL.")
        }
        let token = try await googleToken(manual: options.googleAccessToken)
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.googlePayload(story, video: raw, filename: video.lastPathComponent))
        let data: Data
        let response: URLResponse
        do { (data, response) = try await googleRequest(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw LibraryOperationError.requestFailed("Google upload could not complete. Check your connection; check the sheet before retrying to avoid a duplicate upload.") }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibraryOperationError.requestFailed("Google upload returned no receipt. Sign in with npx clasp login using an allowed account; check the sheet before retrying.")
        }
        guard object["status"] as? String == "success", let id = object["id"] as? Int,
              let preview = object["previewUrl"] as? String, let timestamp = object["timestamp"] as? String else {
            throw LibraryOperationError.invalidInput("Google upload did not return a successful receipt. Check the sheet before retrying.")
        }
        return LibraryUploadResult(message: "Uploaded to Google Drive / Sheets · row \(id)", receipt: .init(id: id, previewURL: preview, thumbnailURL: object["thumbnailUrl"] as? String ?? "", uploadedAt: timestamp))
    }

    static func googlePayload(_ story: Story, video: Data, filename: String) -> [String: String] {
        var seen: Set<String> = []
        return ["title": story.title, "base64Video": video.base64EncodedString(), "fileName": filename,
                "mimeType": mimeType(filename), "hashtags": (story.hashtags ?? []).joined(separator: " "),
                "websiteLinks": (story.sourceLinks ?? []).compactMap(\.webURL).map(\.absoluteString).filter { seen.insert($0).inserted }.joined(separator: "\n")]
    }

    private static func mimeType(_ filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        default: return "video/mp4"
        }
    }

    private func localVideoURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.isFileURL, ["mp4", "mov", "webm"].contains(url.pathExtension.lowercased()) else {
            throw LibraryOperationError.invalidInput("Upload needs an imported local MP4, MOV or WebM video. Use Add video first.")
        }
        return url
    }

    private func googleToken(manual: String) async throws -> String {
        if let token = environmentToken()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty { return token }
        if let data = try readOptional(".clasprc.json") {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = object["tokens"] as? [String: Any], let credentials = tokens["default"] as? [String: Any],
                  let clientID = credentials["client_id"] as? String, let secret = credentials["client_secret"] as? String,
                  let refresh = credentials["refresh_token"] as? String else {
                throw LibraryOperationError.invalidInput("The clasp login cannot be read. Run npx clasp login again.")
            }
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var components = URLComponents()
            components.queryItems = ["client_id": clientID, "client_secret": secret, "refresh_token": refresh, "grant_type": "refresh_token"].map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            let data: Data
            let response: URLResponse
            do { (data, response) = try await httpClient.data(for: request) }
            catch is CancellationError { throw CancellationError() }
            catch { throw LibraryOperationError.requestFailed("Could not refresh Google sign-in. Check your connection, then run npx clasp login if needed.") }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["access_token"] as? String, !token.isEmpty else {
                throw LibraryOperationError.requestFailed("Google sign-in has expired or was rejected. Run npx clasp login again.")
            }
            return token
        }
        let token = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw LibraryOperationError.invalidInput("Set up Google upload: run npx clasp login once, or enter a Google access token in the upload sheet.") }
        return token
    }

    private func googleRequest(_ initial: URLRequest) async throws -> (Data, URLResponse) {
        var request = initial
        for _ in 0..<6 {
            let (data, response) = try await googleHTTPClient.data(for: request)
            guard let http = response as? HTTPURLResponse, [301, 302, 303, 307, 308].contains(http.statusCode) else { return (data, response) }
            guard let location = http.value(forHTTPHeaderField: "Location"), let url = URL(string: location, relativeTo: response.url)?.absoluteURL,
                  url.scheme == "https", let host = url.host, ["script.google.com", "script.googleusercontent.com"].contains(host) else {
                throw LibraryOperationError.requestFailed("Google upload redirected to sign-in or an unexpected host.")
            }
            // Apps Script consumes the POST, then redirects to a GET-only receipt.
            request = URLRequest(url: url, timeoutInterval: 300)
            request.httpMethod = "GET"
        }
        throw LibraryOperationError.requestFailed("Too many Google upload redirects.")
    }
}
