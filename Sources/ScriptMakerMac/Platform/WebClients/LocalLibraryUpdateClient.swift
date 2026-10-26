import Foundation
import NewsSearch

/// Direct news search and publisher images, matching ScriptMaker's non-AI enrichment.
struct LocalLibraryUpdateClient: LibraryUpdating {
    let httpClient: HTTPClient
    let news: @MainActor @Sendable () throws -> (client: any NewsSearching, limit: Int)
    var imageNews: (@MainActor @Sendable () throws -> (client: any NewsSearching, limit: Int))? = nil

    func update(_ kind: LibraryUpdate, story: Story) async throws -> LibraryUpdateResult {
        let title = story.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw LibraryOperationError.invalidInput("Enter a title before fetching related news.") }
        try Task.checkCancellation()
        if kind == .hashtags { return LibraryUpdateResult(hashtags: Self.hashtags(for: title)) }
        if kind == .news { return LibraryUpdateResult(news: try await search(title)) }
        let known = Set(story.imageURLs ?? [])
        var links = (story.sourceLinks ?? []).filter { link in
            guard let url = Self.articleURL(link.url) else { return false }
            return url.host?.lowercased() != "news.google.com"
        }
        if links.isEmpty || !known.isEmpty {
            links += try await search(title, forImages: true, minimumLimit: min(60, known.count + 12))
        }
        var seen: Set<String> = []
        links = links.filter { seen.insert($0.url).inserted }
        var images: [String: Data] = [:]
        var warnings: [String] = []
        let candidates = Array(links.prefix(36))
        for start in stride(from: 0, to: candidates.count, by: 6) {
            try Task.checkCancellation()
            let batch = candidates[start..<min(start + 6, candidates.count)]
            let outcomes = await withTaskGroup(of: (String?, Data?, String?).self) { group in
                for link in batch {
                    group.addTask {
                        do {
                            guard let url = Self.articleURL(link.url) else { throw LibraryOperationError.invalidInput("Invalid article URL") }
                            let (data, response) = try await fetch(url)
                            let html = String(decoding: data, as: UTF8.self)
                            let imageURLs = Self.imageURLs(in: html, baseURL: response.url ?? url)
                            var imageFailures: [String] = []
                            for image in imageURLs where !known.contains(image.absoluteString) {
                                do {
                                    var request = URLRequest(url: image, timeoutInterval: 12)
                                    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                                    request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
                                    request.setValue("image/*", forHTTPHeaderField: "Accept")
                                    let (bytes, imageResponse) = try await httpClient.data(for: request)
                                    guard let http = imageResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                                          http.mimeType?.hasPrefix("image/") == true, !bytes.isEmpty else { imageFailures.append("Publisher rejected the image or returned non-image data."); continue }
                                    return (image.absoluteString, bytes, nil)
                                } catch is CancellationError { throw CancellationError() }
                                catch { imageFailures.append(StringFormatting.errorMessage(error)) }
                            }
                            return (nil, nil, imageURLs.isEmpty ? "No publisher image at \(link.source)." : imageFailures.first.map { "\(link.source): \($0)" })
                        } catch { return (nil, nil, error is CancellationError ? "Image fetch cancelled." : error.localizedDescription) }
                    }
                }
                var values: [(String?, Data?, String?)] = []
                for await value in group { values.append(value) }
                return values
            }
            for (url, data, warning) in outcomes {
                if let url, let data { images[url] = data }
                if let warning { warnings.append(warning) }
            }
            if images.count >= 6 { break }
        }
        try Task.checkCancellation()
        guard !images.isEmpty else {
            if !known.isEmpty { return LibraryUpdateResult(images: [], warnings: ["No additional publisher images found. Existing images retained."]) }
            throw LibraryOperationError.requestFailed("No usable publisher images found. \(warnings.prefix(3).joined(separator: " "))")
        }
        return LibraryUpdateResult(images: images.keys.sorted(), warnings: Array(warnings.prefix(3)), imagePreviews: images)
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 ScriptMakerMac"

    private func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LibraryOperationError.requestFailed("News request failed at \(url.host ?? "publisher").")
        }
        return (data, http)
    }

    private func search(_ title: String, forImages: Bool = false, minimumLimit: Int = 0) async throws -> [StorySourceLink] {
        do {
            let configured = try await (forImages ? imageNews ?? news : news)()
            let articles = try await configured.client.search(title, limit: max(configured.limit, minimumLimit))
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
        imageURLs(in: html, baseURL: baseURL).first
    }

    static func imageURLs(in html: String, baseURL: URL) -> [URL] {
        var result: [URL] = []
        let pattern = #"<meta\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
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
            if !result.contains(url) { result.append(url) }
        }
        return result
    }
}
