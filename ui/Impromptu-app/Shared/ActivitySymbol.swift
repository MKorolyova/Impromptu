//
//  ActivitySymbol.swift
//  Impromptu-app
//
//  Compiled into both the app and the widget extension.
//

import Foundation

/// SF Symbol for an activity, guessed from its name until activities carry real icons (`iconId`).
nonisolated enum ActivitySymbol {
    // First match wins, so more specific words come first ("working out" before "work").
    private static let keywords: [(words: [String], symbol: String)] = [
        (["do not disturb", "dnd"], "moon.fill"),
        (["gym", "working out", "boxing", "pilates", "martial"], "dumbbell.fill"),
        (["shop", "errand", "grocery"], "bag.fill"),
        (["gaming", "board games", "puzzle"], "gamecontroller.fill"),
        (["coffee", "café", "cafe"], "cup.and.saucer.fill"),
        (["eat", "lunch", "dinner", "breakfast", "brunch", "snack", "takeout", "cooking", "baking", "meal"], "fork.knife"),
        (["bar", "party", "partying", "karaoke"], "wineglass.fill"),
        (["code", "coding", "debug", "programming", "release", "reviewing code"], "chevron.left.forwardslash.chevron.right"),
        (["study", "studying", "class", "homework", "exam", "course", "library", "reading", "researching"], "book.fill"),
        (["work", "working", "meeting", "conference", "emails", "presenting", "interview"], "briefcase.fill"),
        (["call", "on call"], "phone.fill"),
        (["run", "jog"], "figure.run"),
        (["walk", "walking", "hiking"], "figure.walk"),
        (["cycling", "bike"], "bicycle"),
        (["yoga", "meditat", "stretch"], "figure.mind.and.body"),
        (["swim", "surf", "beach", "kayak"], "water.waves"),
        (["sport", "basketball", "soccer", "tennis", "golf", "game"], "sportscourt.fill"),
        (["music", "concert", "instrument", "playing music", "dancing", "podcast"], "music.note"),
        (["movie", "tv", "watching", "binge", "streaming"], "tv.fill"),
        (["sleep", "nap", "napping", "relax", "lounging", "chilling"], "bed.double.fill"),
        (["travel", "flight", "sightseeing", "exploring"], "airplane"),
        (["drive", "driving", "commut"], "car.fill"),
        (["hang", "friends", "family", "date", "wedding", "birthday", "networking"], "person.2.fill"),
        (["design", "drawing", "painting", "writing", "crafting", "photo", "video"], "paintbrush.fill"),
        (["clean", "chores", "laundry", "fixing", "building", "garden"], "house.fill"),
        (["sick", "recovering", "doctor", "appointment"], "cross.case.fill"),
        // Last, so names that merely contain "free" match something more specific first.
        (["free"], "hand.wave.fill"),
    ]

    static func name(for activityName: String) -> String {
        let lowered = activityName.lowercased()
        return keywords.first { entry in entry.words.contains { lowered.contains($0) } }?.symbol ?? "sparkles"
    }
}
