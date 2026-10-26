import Foundation

protocol ScriptDetailDataSourceProtocol: Sendable {
    func load() throws -> [ScriptDetailItem]
    func save(_ items: [ScriptDetailItem]) throws
}

struct SavedScriptDetailDataSource: ScriptDetailDataSourceProtocol {
    private let store: KeyValueStore
    private let storage: (any CollectionDataStoring)?
    private let key: String
    init(store: KeyValueStore, key: String = "script_detail_items", storage: (any CollectionDataStoring)? = nil) { self.store = store; self.key = key; self.storage = storage }
    func load() throws -> [ScriptDetailItem] {
        guard let data = try storage?.read() ?? store.data(forKey: key) else { return [] }
        do { return try JSONDecoder().decode([ScriptDetailItem].self, from: data) }
        catch { throw PersistenceError.unreadable("Script Detail items") }
    }
    func save(_ items: [ScriptDetailItem]) throws {
        let data = try JSONEncoder().encode(items)
        try storage?.write(data)
        store.set(data, forKey: key)
    }
}

actor LocalScriptDetailRepository: ScriptDetailRepository {
    private let dataSource: any ScriptDetailDataSourceProtocol
    private var cache: [ScriptDetailItem]?
    init(dataSource: any ScriptDetailDataSourceProtocol) { self.dataSource = dataSource }
    func all() throws -> [ScriptDetailItem] { try loadCached() }
    func save(_ item: ScriptDetailItem) throws {
        var items = try loadCached()
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        try persist(items)
    }
    func remove(id: String) throws {
        var items = try loadCached()
        items.removeAll { $0.id == id }
        try persist(items)
    }
    func invalidateCache() { cache = nil }
    private func loadCached() throws -> [ScriptDetailItem] {
        if let cache { return cache }
        let items = try dataSource.load()
        cache = items
        return items
    }
    private func persist(_ items: [ScriptDetailItem]) throws {
        try dataSource.save(items)
        cache = items
    }
}
