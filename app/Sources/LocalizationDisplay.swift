// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

// Simplified Chinese localization, phase 2 (display-point lookup).
//
// Many user-facing strings in this app are first stored in plain `String`
// properties (a row's `title`, a model's `summary`, a guide step's `text`,
// ...) and only later handed to `Text`. A stored `String` never looks
// itself up in the Localizable catalog, so those strings stayed English
// even with `Localizable.xcstrings` bundled.
//
// `portholeLocalized` performs that lookup at the point where a string is
// actually rendered. It is deliberately only applied to display text:
//   - If the string is a key in the Localizable table, its translation for
//     the current system language is returned.
//   - If it is not a key (a game name, a file path, a value built from
//     user data, ...), `NSLocalizedString` returns the string itself,
//     unchanged.
// The stored value is never modified, so identifiers, focus IDs, docs
// topics, persisted keys and equality comparisons that reuse the same
// property keep working with the original English value.
//
// Known limitation: a string that was already interpolated at runtime
// (for example "3 of 5") cannot match a catalog key, because the catalog
// keys keep the source form with its interpolation; such strings pass
// through unchanged and stay English until they are handled separately.
extension String {
    var portholeLocalized: String { NSLocalizedString(self, comment: "") }
}
