import Foundation

/// Direct news search and publisher images, matching ScriptMaker's non-AI enrichment.
struct LocalLibraryUpdateClient: LibraryUpdating {
    let httpClient: HTTPClient

    func update(_ kind: LibraryUpdate, story: Story, engine: String, instruction: String,
                localJSON: Bool, delay: TimeInterval, serverURL: URL?) async throws -> LibraryUpdateResult {
        let title = story.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw APIError.malformed("Enter a title before fetching related news.") }
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
                        guard let url = link.webURL else { throw APIError.malformed("Invalid article URL") }
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
                            throw APIError.transport("Publisher image is unavailable at \(link.source).")
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
        guard !images.isEmpty else { throw APIError.transport("No usable article images found. \(outcomes.compactMap { $0.1 }.joined(separator: " "))") }
        return LibraryUpdateResult(images: images, warnings: outcomes.compactMap { $0.1 })
    }

    private func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 ScriptMakerMac", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.transport("News request failed at \(url.host ?? "publisher").")
        }
        return (data, http)
    }

    private func search(_ title: String) async throws -> [StorySourceLink] {
        let sources = [("https://www.bing.com/news/search", "q"), ("https://news.google.com/rss/search", "q")]
        var failures: [String] = []
        for (endpoint, key) in sources {
            do {
                var components = URLComponents(string: endpoint)!
                components.queryItems = [URLQueryItem(name: key, value: title)] + (endpoint.contains("bing.com")
                    ? [URLQueryItem(name: "format", value: "rss")]
                    : [URLQueryItem(name: "hl", value: "en-IN"), URLQueryItem(name: "gl", value: "IN"), URLQueryItem(name: "ceid", value: "IN:en")])
                let (data, _) = try await fetch(components.url!)
                let parser = LibraryNewsFeedParser()
                let xml = XMLParser(data: data)
                xml.shouldResolveExternalEntities = false
                xml.delegate = parser
                guard xml.parse() else { throw APIError.malformed("Invalid news feed") }
                var seen: Set<String> = []
                let links = parser.items.compactMap { item -> StorySourceLink? in
                    guard let url = Self.articleURL(item.url), seen.insert(url.absoluteString).inserted else { return nil }
                    return StorySourceLink(title: item.title, url: url.absoluteString, source: item.source.isEmpty ? (url.host ?? "News") : item.source)
                }
                if !links.isEmpty { return Array(links.prefix(6)) }
                failures.append("\(components.host ?? "News search"): no matching articles.")
            } catch is CancellationError { throw CancellationError() }
            catch { failures.append(error.localizedDescription) }
        }
        throw APIError.transport("Could not find related news. \(failures.joined(separator: " "))")
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

private final class LibraryNewsFeedParser: NSObject, XMLParserDelegate {
    var items: [StorySourceLink] = []
    private var inItem = false
    private var element = ""
    private var title = ""
    private var link = ""
    private var source = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        element = name
        if name == "item" { inItem = true; title = ""; link = ""; source = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch element { case "title": title += string; case "link": link += string; case "source": source += string; default: break }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item" {
            items.append(.init(title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: link.trimmingCharacters(in: .whitespacesAndNewlines), source: source.trimmingCharacters(in: .whitespacesAndNewlines)))
            inItem = false
        }
        element = ""
    }
}
