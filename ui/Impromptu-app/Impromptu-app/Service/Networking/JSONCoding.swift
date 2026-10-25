//
//  JSONCoding.swift
//  Impromptu-app
//

import Foundation

extension JSONEncoder {
    /// Dates as ISO-8601 with milliseconds, matching `Date.toJSON()` on the server.
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(iso8601WithFractionalSeconds))
        }
        return encoder
    }()
}

extension JSONDecoder {
    /// Accepts ISO-8601 dates with or without fractional seconds.
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: iso8601WithFractionalSeconds) { return date }
            if let date = try? Date(string, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
        }
        return decoder
    }()
}

private nonisolated let iso8601WithFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
