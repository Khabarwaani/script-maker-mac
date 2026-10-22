import Foundation
import NewsSearch

/// Direct news search and publisher images, matching ScriptMaker's non-AI enrichment.
struct LocalLibraryUpdateClient: LibraryUpdating {
    let httpClient: HTTPClient
    let news: @MainActor @Sendable () throws -> (client: any NewsSearching, limit: Int)

    func update(_ kind: LibraryUpdate, story: Story, engine: String, instruction: String,
                localJSON: Bool, delay: TimeInterval, serverURL: URL?) async throws -> LibraryUpdateResult {
        let title = story.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw LibraryOperationError.invalidInput("Enter a title before fetching related news.") }
        try Task.checkCancellation()
        if kind == .hashtags { return LibraryUpdateResult(hashtags: Self.hashtags(for: title)) }
        if kind == .news { return LibraryUpdateResult(news: try await search(title)) }
        let links: [StorySourceLink]
        if let existing = story.sourceLinks, !existing.isEmpty { links = existing }
        else { links = try await search(title) }
        let outcomes = await withTaskGroup(of: (String?, String?).self) { group in
            for link in links.prefix(6) {
                group.addTask {
                    do {
                        guard let url = link.webURL else { throw LibraryOperationError.invalidInput("Invalid article URL") }
                        let (data, response) = try await fetch(url)
                        let html = String(decoding: data, as: UTF8.self)
                        guard let image = Self.imageURL(in: html, baseURL: response.url ?? url) else {
                            return (nil, "No article image at \(link.source).")
                        }
                        var request = URLRequest(url: image, timeoutInterval: 10)
                        request.httpMethod = "HEAD"
                        var (_, imageResponse) = try await httpClient.data(for: request)
                        if (imageResponse as? HTTPURLResponse)?.statusCode != 200 {
                            request.httpMethod = "GET"
                            request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
                            (_, imageResponse) = try await httpClient.data(for: request)
                        }
                        guard let http = imageResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                              http.mimeType?.hasPrefix("image/") == true else {
                            throw LibraryOperationError.requestFailed("Publisher image is unavailable at \(link.source).")
                        }
                        return (image.absoluteString, nil)
                    } catch { return (nil, error is CancellationError ? "Image fetch cancelled." : error.localizedDescription) }
                }
            }
            var values: [(String?, String?)] = []
            for await value in group { values.append(value) }
            return values
        }
        try Task.checkCancellation()
        let images = Array(Set(outcomes.compactMap { $0.0 })).sorted()
        guard !images.isEmpty else { throw LibraryOperationError.requestFailed("No usable article images found. \(outcomes.compactMap { $0.1 }.joined(separator: " "))") }
        return LibraryUpdateResult(images: images, warnings: outcomes.compactMap { $0.1 })
    }

    private func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 ScriptMakerMac", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LibraryOperationError.requestFailed("News request failed at \(url.host ?? "publisher").")
        }
        return (data, http)
    }

    private func search(_ title: String) async throws -> [StorySourceLink] {
        do {
            let configured = try await news()
            let articles = try await configured.client.search(title, limit: configured.limit)
            var seen: Set<String> = []
            let links = articles.compactMap { article -> StorySourceLink? in
                guard let url = Self.articleURL(article.url.absoluteString), seen.insert(url.absoluteString).inserted else { return nil }
                return StorySourceLink(title: article.title, url: url.absoluteString, source: article.source.isEmpty ? (url.host ?? "News") : article.source)
            }
            guard !links.isEmpty else { throw LibraryOperationError.requestFailed("No matching articles.") }
            return links
        } catch is CancellationError { throw CancellationError() }
        catch {
            throw LibraryOperationError.requestFailed("Could not find related news. \(error.localizedDescription)")
        }
    }

    static func articleURL(_ value: String) -> URL? {
        guard var url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        if url.host?.hasSuffix("bing.com") == true,
           let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
           let direct = URL(string: target), ["http", "https"].contains(direct.scheme ?? ""), direct.host != nil { url = direct }
        return url
    }

    static func hashtags(for title: String) -> [String] {
        let stop: Set<String> = ["the", "and", "for", "with", "from", "this", "that", "into", "after", "over", "has", "have", "are", "was", "will", "news", "today"]
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}]+"#) else { return [] }
        let words = regex.matches(in: title, range: NSRange(title.startIndex..., in: title)).compactMap { match -> String? in
            guard let range = Range(match.range, in: title) else { return nil }
            let word = String(title[range])
            return stop.contains(word.lowercased()) ? nil : word
        }
        var seen: Set<String> = []
        return Array(words.map { "#" + $0 }.filter { seen.insert($0.lowercased()).inserted }.prefix(5))
    }

    static func imageURL(in html: String, baseURL: URL) -> URL? {
        let pattern = #"<meta\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            let attributes = #"([\w:-]+)\s*=\s*["']([^"']*)["']"#
            guard let attributeRegex = try? NSRegularExpression(pattern: attributes) else { continue }
            var values: [String: String] = [:]
            for attribute in attributeRegex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                if let name = Range(attribute.range(at: 1), in: tag), let value = Range(attribute.range(at: 2), in: tag) {
                    values[String(tag[name]).lowercased()] = String(tag[value])
                }
            }
            let property = (values["property"] ?? values["name"] ?? "").lowercased()
            guard ["og:image", "og:image:secure_url", "twitter:image", "twitter:image:src"].contains(property),
                  let content = values["content"], let url = URL(string: content.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: baseURL)?.absoluteURL,
                  ["http", "https"].contains(url.scheme ?? "") else { continue }
            return url
        }
        return nil
    }
}
