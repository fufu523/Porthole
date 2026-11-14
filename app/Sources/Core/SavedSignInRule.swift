// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// When a Steam game may start from Steam's saved (offline) sign-in although a network is there: the rule only, so a host test can check it. DockOffline asks it.
enum SavedSignInRule {
    /// How long after a game's last online start the saved sign-in is used; the next start goes online and renews it.
    static let maxAge: TimeInterval = 14 * 24 * 3600

    static func decide(enabled: Bool, override: Int?, settingOn: Bool, forcedOnline: Bool, accountSaved: Bool, verified: Date?, now: Date = Date()) -> (use: Bool, why: String) {
        guard enabled else { return (false, "offline logon is off") }
        if override == 1 { return (false, "the game asks for an online sign-in") }
        if override == nil, !settingOn { return (false, "switched off in Settings") }
        if forcedOnline { return (false, "Steam could not use its saved sign-in last time") }
        guard accountSaved else { return (false, "Steam has no offline sign-in saved yet") }
        guard let when = verified else { return (false, "this game has not started online yet") }
        let age = now.timeIntervalSince(when)
        if age > maxAge { return (false, "the last online start was \(Int(age / 86400)) days ago") }
        return (true, "this game started online \(max(0, Int(age / 3600))) hours ago")
    }
}
