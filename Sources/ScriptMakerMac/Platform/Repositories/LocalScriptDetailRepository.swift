import Foundation

/// Data source interface for persisting Script Detail items.
protocol ScriptDetailDataSourceProtocol: Sendable {
    func load() -> [ScriptDetailItem]
    func save(_ items: [ScriptDetailItem])
}

/// Key-value storage implementation for Script Detail items, isolated from Library stories.
final class UserDefaultsScriptDetailDataSource: ScriptDetailDataSourceProtocol, @unchecked Sendable {
    private let key: String
    private let userDefaults: UserDefaults

    init(key: String = "script_detail_items", userDefaults: UserDefaults = .standard) {
        self.key = key
        self.userDefaults = userDefaults
    }

    func load() -> [ScriptDetailItem] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ScriptDetailItem].self, from: data)) ?? []
    }

    func save(_ items: [ScriptDetailItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        userDefaults.set(data, forKey: key)
    }
}

/// Platform repository for Script Detail scenes with memory cache and independent persistence.
final class LocalScriptDetailRepository: ScriptDetailRepository, @unchecked Sendable {
    private let dataSource: any ScriptDetailDataSourceProtocol
    private var cache: [ScriptDetailItem]?
    private let lock = NSLock()

    init(dataSource: any ScriptDetailDataSourceProtocol = UserDefaultsScriptDetailDataSource()) {
        self.dataSource = dataSource
    }

    func all() async -> [ScriptDetailItem] {
        loadCached()
    }

    func save(_ item: ScriptDetailItem) async {
        var items = loadCached()
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        persist(items)
    }

    func remove(id: String) async {
        var items = loadCached()
        items.removeAll { $0.id == id }
        persist(items)
    }

    func invalidateCache() {
        lock.withLock { cache = nil }
    }

    private func loadCached() -> [ScriptDetailItem] {
        lock.withLock {
            if let cached = cache { return cached }
            let loaded = dataSource.load()
            cache = loaded
            return loaded
        }
    }

    private func persist(_ items: [ScriptDetailItem]) {
        lock.withLock { cache = items }
        dataSource.save(items)
    }
}
