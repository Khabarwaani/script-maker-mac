import Foundation

struct RegionGeo: Equatable, Hashable, Sendable {
    let code: String
    let name: String

    var flag: String {
        guard code.count == 2 else { return "🌐" }
        let base: UInt32 = 127397
        var s = ""
        for v in code.uppercased().unicodeScalars {
            guard let scalar = UnicodeScalar(base + v.value) else { return "🌐" }
            s.unicodeScalars.append(scalar)
        }
        return s
    }

    var displayTitle: String {
        "\(flag) \(name) (\(code))"
    }

    private static let enLocale = Locale(identifier: "en_US")

    static let allGeos: [RegionGeo] = {
        let regions = Locale.Region.isoRegions.filter {
            $0.identifier.count == 2 && $0.identifier.allSatisfy { $0.isASCII && $0.isUppercase }
        }
        return regions.compactMap { reg in
            guard let name = enLocale.localizedString(forRegionCode: reg.identifier) else { return nil }
            return RegionGeo(code: reg.identifier, name: name)
        }
    }()

    private static let aliases: [String: String] = [
        "usa": "US",
        "united states of america": "US",
        "uk": "GB",
        "great britain": "GB",
        "britain": "GB",
        "england": "GB",
        "uae": "AE",
        "united arab emirates": "AE",
        "south korea": "KR",
        "korea": "KR",
        "russia": "RU",
        "taiwan": "TW"
    ]

    static func resolve(_ input: String) -> RegionGeo? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let upper = trimmed.uppercased()
        if upper.count == 2, let match = allGeos.first(where: { $0.code == upper }) {
            return match
        }

        let lower = trimmed.lowercased()
        if let aliasCode = aliases[lower], let match = allGeos.first(where: { $0.code == aliasCode }) {
            return match
        }

        if let match = allGeos.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }

        return nil
    }
}

enum NewsFeedOrder: String, CaseIterable, Hashable, Sendable {
    case googleThenBing = "Google, then Bing"
    case bingThenGoogle = "Bing, then Google"
    case googleOnly = "Google only"
    case bingOnly = "Bing only"

    var providers: [String] {
        switch self {
        case .googleThenBing: ["google", "bing"]
        case .bingThenGoogle: ["bing", "google"]
        case .googleOnly: ["google"]
        case .bingOnly: ["bing"]
        }
    }
}

struct NewsDiscoverySettings: Equatable, Sendable {
    var searchDuration: TimeInterval = 24 * 3600
    var cacheDuration: TimeInterval = 6 * 3600
    var providerOrder: NewsFeedOrder = .googleThenBing
    var region = "IN"
    var language = "en"
    var location = "India"

    var cacheIdentifier: String {
        "\(providerOrder.providers.joined(separator: ","))|\(region)|\(language)|\(location.lowercased())|\(searchDuration)|\(cacheDuration)"
    }

    var regionGeo: RegionGeo {
        RegionGeo.resolve(region) ?? RegionGeo.resolve(location) ?? RegionGeo(code: "IN", name: "India")
    }

    mutating func setRegionGeo(_ input: String) throws {
        guard let geo = RegionGeo.resolve(input) else {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NewsSettingsError.invalid(
                "\"\(trimmed)\" is not a recognized country or region geo. Enter a country code or name (e.g. IN, India, US, United States). Cities and states are not supported."
            )
        }
        self.region = geo.code
        self.location = geo.name
    }

    func validated() throws -> Self {
        var value = self
        value.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedLoc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReg = region.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedLoc.isEmpty, RegionGeo.resolve(trimmedLoc) == nil {
            throw NewsSettingsError.invalid(
                "\"\(trimmedLoc)\" is not a recognized country or region geo. Enter a country code or name (e.g. IN, India, US, United States). Cities and states are not supported."
            )
        }
        if !trimmedReg.isEmpty, RegionGeo.resolve(trimmedReg) == nil {
            throw NewsSettingsError.invalid(
                "\"\(trimmedReg)\" is not a recognized country or region geo. Enter a country code or name (e.g. IN, India, US, United States). Cities and states are not supported."
            )
        }

        let geo: RegionGeo
        if let gLoc = RegionGeo.resolve(trimmedLoc), trimmedLoc.caseInsensitiveCompare("India") != .orderedSame {
            geo = gLoc
        } else if let gReg = RegionGeo.resolve(trimmedReg), trimmedReg.caseInsensitiveCompare("IN") != .orderedSame {
            geo = gReg
        } else if let gLoc = RegionGeo.resolve(trimmedLoc) {
            geo = gLoc
        } else if let gReg = RegionGeo.resolve(trimmedReg) {
            geo = gReg
        } else {
            geo = RegionGeo(code: "IN", name: "India")
        }
        value.region = geo.code
        value.location = geo.name

        guard searchDuration.isFinite, (0...366 * 86400).contains(searchDuration),
              cacheDuration.isFinite, (0...366 * 86400).contains(cacheDuration) else {
            throw NewsSettingsError.invalid("Search and cache durations must be between 0 and 8784 hours.")
        }
        guard !value.language.isEmpty, value.language.count <= 35,
              value.language.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else {
            throw NewsSettingsError.invalid("Enter a language code, such as en or hi.")
        }
        return value
    }
}

enum NewsSettingsError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
