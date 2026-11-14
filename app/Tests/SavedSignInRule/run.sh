#!/bin/bash
# Compiles SavedSignInRule (Sources/Core/SavedSignInRule.swift) for the Mac and checks when a start may use Steam's saved sign-in.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
cat > "$OUT/main.swift" <<'S'
import Foundation
var failed = 0
func check(_ ok: Bool, _ message: String) { print(ok ? "ok:   \(message)" : "FAIL: \(message)"); if !ok { failed += 1 } }
let now = Date()
func rule(enabled: Bool = true, override: Int? = nil, settingOn: Bool = true, forced: Bool = false, saved: Bool = true, verified: Date? = Date().addingTimeInterval(-3600)) -> (use: Bool, why: String) {
    SavedSignInRule.decide(enabled: enabled, override: override, settingOn: settingOn, forcedOnline: forced, accountSaved: saved, verified: verified, now: now)
}
check(rule().use, "a game that started online an hour ago starts from the saved sign-in")
check(!rule(enabled: false).use, "offline logon switched off: online")
check(!rule(settingOn: false).use, "switched off in Settings: online")
check(rule(override: 0, settingOn: false).use, "the game's own choice for the saved sign-in wins over the setting")
check(!rule(override: 1).use, "the game asks for online: online")
check(!rule(forced: true).use, "after Steam refused it once: online")
check(!rule(override: 0, forced: true).use, "even when the game asked for it, a refusal means one online start")
check(!rule(saved: false).use, "no offline sign-in saved yet: online")
check(!rule(verified: nil).use, "a game that never started online: online")
check(rule(verified: now.addingTimeInterval(-13 * 86400)).use, "13 days after the online start: still the saved sign-in")
check(!rule(verified: now.addingTimeInterval(-15 * 86400)).use, "15 days after: online, which renews it")
check(rule(verified: now.addingTimeInterval(+60)).use, "a clock that moved back does not break it")
check(rule(verified: now.addingTimeInterval(-3 * 3600)).why.contains("3 hours"), "the reason names the age")
print(failed == 0 ? "\nALL PASSED" : "\n\(failed) FAILED")
exit(failed == 0 ? 0 : 1)
S
swiftc -swift-version 5 -o "$OUT/t" "$OUT/main.swift" "$HERE/../../Sources/Core/SavedSignInRule.swift"
"$OUT/t"
rm -rf "$OUT"
