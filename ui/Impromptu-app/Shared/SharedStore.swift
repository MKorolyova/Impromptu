//
//  SharedStore.swift
//  Impromptu-app
//
//  Compiled into both the app and the widget extension.
//

import Foundation

/// A typed handle for one value persisted in the shared store.
nonisolated struct SharedKey<Value: Codable & Sendable>: Sendable {
    let fileName: String
}

/// JSON-file persistence inside the App Group container.
/// The app writes, the widget reads. Add new `SharedKey`s for new widget data.
nonisolated struct SharedStore: Sendable {
    static let standard = SharedStore(directory: AppGroup.containerURL)

    let directory: URL

    func load<Value>(_ key: SharedKey<Value>) -> Value? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    func save<Value>(_ value: Value, for key: SharedKey<Value>) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        try data.write(to: url(for: key), options: .atomic)
    }

    func remove<Value>(_ key: SharedKey<Value>) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    private func url<Value>(for key: SharedKey<Value>) -> URL {
        directory.appending(path: key.fileName)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
