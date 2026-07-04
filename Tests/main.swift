import Foundation

// Assert-based check for AppModel: compiled together with Sources/Model.swift
// as a bare binary (never -O, or asserts vanish). Run via `./build.sh check`.

func scratchDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("workout-interval-check-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let dir = scratchDir()

// Defaults on first launch
let m = AppModel(storageDirectory: dir)
assert(m.phase == .idle)
assert(m.intervalMinutes == 60)
assert(m.exercises.map(\.name) == ["Pushups", "Situps"])
assert(m.exercises.map(\.targetReps) == [15, 15])
assert(m.secondsLeft == 3600)
assert(m.countdownText == "1:00:00")
assert(m.iconSymbol == "figure.run")

// Start / pause / resume / reset math
m.start()
guard case .running(let end) = m.phase else { fatalError("expected running") }
assert(abs(end.timeIntervalSinceNow - 3600) < 2)
assert(m.iconSymbol == "timer")
m.pause()
guard case .paused(let remaining) = m.phase else { fatalError("expected paused") }
assert(abs(remaining - 3600) < 2)
m.resume()
guard case .running = m.phase else { fatalError("expected running after resume") }
m.reset()
assert(m.phase == .idle && m.secondsLeft == 3600)

// Fire → log both (one adjusted) → totals + completed round + auto-restart
m.start()
m.fire()
assert(m.phase == .due)
assert(m.iconSymbol == "exclamationmark.circle.fill")
assert(m.dueItems.count == 2 && m.dueItems[0].targetReps == 15)
m.log(id: m.dueItems[0].id, reps: 10)  // did 10 instead of 15
m.log(id: m.dueItems[0].id, reps: 15)
assert(m.sessionReps["Pushups"] == 10 && m.sessionReps["Situps"] == 15)
assert(m.lifetimeReps["Pushups"] == 10 && m.lifetimeReps["Situps"] == 15)
assert(m.sessionRounds == 1 && m.lifetimeRounds == 1)
guard case .running = m.phase else { fatalError("expected auto-restart after round") }

// Fire → log one, skip one → reps count, round does not
m.fire()
m.log(id: m.dueItems[0].id, reps: 15)
m.skip(id: m.dueItems[0].id)
assert(m.sessionReps["Pushups"] == 25)
assert(m.sessionReps["Situps"] == 15)
assert(m.sessionRounds == 1 && m.lifetimeRounds == 1)
guard case .running = m.phase else { fatalError("expected auto-restart after skip") }

// Session reset leaves lifetime alone
m.resetSession()
assert(m.sessionReps.isEmpty && m.sessionRounds == 0)
assert(m.lifetimeReps["Pushups"] == 25 && m.lifetimeRounds == 1)

// Interval clamp + CRUD
m.intervalMinutes = 0
assert(m.intervalMinutes == 1)
m.intervalMinutes = 9999
assert(m.intervalMinutes == 480)
m.intervalMinutes = 45
m.addExercise()
assert(m.exercises.count == 3)
m.exercises[2].name = "Squats"
m.exercises[2].targetReps = 20
m.removeExercise(m.exercises[0].id)
assert(m.exercises.map(\.name) == ["Situps", "Squats"])

// Empty exercise list: fire restarts immediately, no round counted
let dir2 = scratchDir()
let m2 = AppModel(storageDirectory: dir2)
m2.exercises = []
m2.start()
m2.fire()
guard case .running = m2.phase else { fatalError("expected restart on empty fire") }
assert(m2.lifetimeRounds == 0 && m2.dueItems.isEmpty)
try? FileManager.default.removeItem(at: dir2)

// Persistence roundtrip: settings/exercises/lifetime survive, session resets
let reloaded = AppModel(storageDirectory: dir)
assert(reloaded.phase == .idle)
assert(reloaded.intervalMinutes == 45)
assert(reloaded.exercises.map(\.name) == ["Situps", "Squats"])
assert(reloaded.exercises.map(\.targetReps) == [15, 20])
assert(reloaded.lifetimeReps["Pushups"] == 25 && reloaded.lifetimeReps["Situps"] == 15)
assert(reloaded.lifetimeRounds == 1)
assert(reloaded.sessionReps.isEmpty && reloaded.sessionRounds == 0)

// Corrupt state file falls back to defaults
try! Data("not json".utf8).write(to: dir.appendingPathComponent("state.json"))
let fallback = AppModel(storageDirectory: dir)
assert(fallback.intervalMinutes == 60 && fallback.exercises.count == 2)

try? FileManager.default.removeItem(at: dir)
print("ALL CHECKS PASSED")
