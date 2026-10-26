import Foundation

protocol StoryDataSourceProtocol: Sendable {
    func load() throws -> [Story]
    func save(_ stories: [Story]) throws
}

struct UserDefaultsStoryDataSource: StoryDataSourceProtocol {
    private let store: KeyValueStore
    init(store: KeyValueStore) { self.store = store }
    func load() throws -> [Story] {
        guard let data = store.data(forKey: "savedStories") else { return [] }
        if let stories = try? JSONDecoder().decode([Story].self, from: data) { return stories }
        if let dictionaries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           dictionaries.allSatisfy({ $0["id"] is String && $0["title"] is String }) {
            return dictionaries.map(StoryMapper.from)
        }
        throw PersistenceError.unreadable("stories")
    }
    func save(_ stories: [Story]) throws {
        store.set(try JSONEncoder().encode(stories), forKey: "savedStories")
    }
}
