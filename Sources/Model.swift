import Foundation
import UserNotifications

struct Exercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var targetReps: Int
    var block: Int = 0            // rotation group; blocks cycle one per interval

    enum CodingKeys: String, CodingKey { case id, name, targetReps, block }
    init(id: UUID = UUID(), name: String, targetReps: Int, block: Int = 0) {
        self.id = id; self.name = name; self.targetReps = targetReps; self.block = block
    }
    // Custom decode: synthesized Codable throws keyNotFound (not the default) for
    // a missing key, so old state.json without `block` would fail to load and wipe
    // the user's exercises + lifetime stats. decodeIfPresent keeps them.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        targetReps = try c.decode(Int.self, forKey: .targetReps)
        block = try c.decodeIfPresent(Int.self, forKey: .block) ?? 0
    }
}

/// One row of the due checklist — a snapshot of an exercise at fire time.
struct DueItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let targetReps: Int
}

enum Phase: Equatable {
    case idle
    case running(end: Date)
    case paused(remaining: TimeInterval)
    case due
}

private struct PersistedState: Codable {
    var intervalMinutes: Int
    var exercises: [Exercise]
    var lifetimeReps: [String: Int]
    var lifetimeRounds: Int
}

// Not @MainActor: Timer's block imports as @Sendable and calling into a
// main-actor method from it is a hard error under the Swift 6 compiler.
// Everything here runs on the main thread by construction instead.
final class AppModel: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var dueItems: [DueItem] = []
    @Published var secondsLeft = 0
    /// Total seconds of the current running stretch — denominator for the UI's
    /// progress ring. Survives pause/resume so the ring doesn't refill on resume.
    @Published var runTotalSeconds = 0
    @Published var justCompletedRound = false

    @Published var intervalMinutes: Int {
        didSet {
            let clamped = min(480, max(1, intervalMinutes))
            if intervalMinutes != clamped { intervalMinutes = clamped }
            if case .idle = phase {
                secondsLeft = intervalMinutes * 60
                runTotalSeconds = secondsLeft
            }
            persist()
        }
    }
    @Published var exercises: [Exercise] { didSet { persist() } }

    // Session stats live only in memory; lifetime stats persist.
    // Both are keyed by trimmed exercise name, so deleting and re-adding
    // "Pushups" keeps its history; a rename starts a fresh stat line.
    @Published var sessionReps: [String: Int] = [:]
    @Published var sessionRounds = 0
    @Published var currentBlock = 0   // in-memory only; resets to first block on launch
    @Published var lifetimeReps: [String: Int] { didSet { persist() } }
    @Published var lifetimeRounds: Int { didSet { persist() } }

    private let storeURL: URL
    private let backupURL: URL
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var authRequested = false
    private var dueTotal = 0
    private var dueLogged = 0

    // UNUserNotificationCenter.current() throws NSInternalInconsistencyException
    // from a bare (non-bundled) binary — this guard keeps the check harness alive.
    private let notificationsAvailable = Bundle.main.bundleIdentifier != nil
    private let notificationID = "interval-due"

    init(storageDirectory: URL? = nil) {
        let dir = storageDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WorkoutInterval", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("state.json")
        backupURL = dir.appendingPathComponent("state.backup.json")

        func decode(_ url: URL) -> PersistedState? {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        }
        // Fall back to the backup mirror if the primary is missing or corrupt,
        // so lifetime totals survive a bad state.json instead of resetting.
        let saved = decode(storeURL) ?? decode(backupURL)
        intervalMinutes = saved?.intervalMinutes ?? 60
        exercises = saved?.exercises
            ?? [Exercise(name: "Pushups", targetReps: 15), Exercise(name: "Situps", targetReps: 15)]
        lifetimeReps = saved?.lifetimeReps ?? [:]
        lifetimeRounds = saved?.lifetimeRounds ?? 0
        secondsLeft = intervalMinutes * 60
        runTotalSeconds = secondsLeft

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        // .common mode, or the countdown freezes while the popover tracks events
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Display helpers

    var iconSymbol: String {
        switch phase {
        case .idle: return "figure.run"
        case .running: return "timer"
        case .paused: return "pause.circle"
        case .due: return "exclamationmark.circle.fill"
        }
    }

    var countdownText: String {
        let s = max(0, secondsLeft)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    func sessionCount(for name: String) -> Int { sessionReps[key(name)] ?? 0 }
    func lifetimeCount(for name: String) -> Int { lifetimeReps[key(name)] ?? 0 }

    // MARK: - Timer intents

    func start() {
        requestAuthIfNeeded()
        beginRunning(seconds: TimeInterval(intervalMinutes * 60))
    }

    func pause() {
        guard case .running(let end) = phase else { return }
        let remaining = max(1, end.timeIntervalSinceNow)
        phase = .paused(remaining: remaining)
        secondsLeft = Int(remaining.rounded(.up))
        cancelPendingNotification()
        endActivity()
    }

    func resume() {
        guard case .paused(let remaining) = phase else { return }
        beginRunning(seconds: remaining, preserveTotal: true)
    }

    func reset() {
        phase = .idle
        dueItems = []
        secondsLeft = intervalMinutes * 60
        runTotalSeconds = secondsLeft
        cancelPendingNotification()
        clearDeliveredNotifications()
        endActivity()
    }

    /// Display refresh + edge detection only — all truth derives from endDate,
    /// so App Nap or system sleep can never corrupt state.
    func tick() {
        guard case .running(let end) = phase else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            fire()
        } else {
            secondsLeft = Int(left.rounded(.up))
        }
    }

    // MARK: - Due checklist

    /// running → due. Internal (not private) so the check harness can drive it.
    func fire() {
        guard case .running = phase else { return }
        endActivity()
        let group = currentGroup()
        guard !group.isEmpty else {
            beginRunning(seconds: TimeInterval(intervalMinutes * 60))
            return
        }
        dueItems = group.map { DueItem(id: $0.id, name: $0.name, targetReps: $0.targetReps) }
        dueTotal = dueItems.count
        dueLogged = 0
        phase = .due
    }

    func log(id: UUID, reps: Int) {
        guard let item = dueItems.first(where: { $0.id == id }) else { return }
        let r = max(0, reps)
        sessionReps[key(item.name), default: 0] += r
        lifetimeReps[key(item.name), default: 0] += r
        dueLogged += 1
        resolve(id)
    }

    func skip(id: UUID) { resolve(id) }

    private func resolve(_ id: UUID) {
        dueItems.removeAll { $0.id == id }
        guard case .due = phase, dueItems.isEmpty else { return }
        // A round only counts as completed when nothing was skipped.
        if dueLogged == dueTotal {
            sessionRounds += 1
            lifetimeRounds += 1
            flashCompletion()
        }
        advanceBlock()   // every interval → next block (regardless of completion/skip)
        clearDeliveredNotifications()
        beginRunning(seconds: TimeInterval(intervalMinutes * 60))
    }

    // MARK: - Stats

    func resetSession() {
        sessionReps = [:]
        sessionRounds = 0
    }

    /// Log reps done off-time (outside a scheduled round). Adds to session +
    /// lifetime totals only — never touches the timer, due checklist, or rounds.
    func logManual(name: String, reps: Int) {
        let r = max(0, reps)
        guard r > 0 else { return }
        sessionReps[key(name), default: 0] += r
        lifetimeReps[key(name), default: 0] += r
    }

    // MARK: - Exercises

    func addExercise() {
        exercises.append(Exercise(name: "Exercise", targetReps: 10, block: blockOrder.last ?? 0))
    }

    func addBlock() {
        exercises.append(Exercise(name: "Exercise", targetReps: 10, block: (blockOrder.last ?? -1) + 1))
    }

    func removeExercise(_ id: UUID) {
        exercises.removeAll { $0.id == id }
    }

    // MARK: - Rotation
    // Blocks cycle one per interval: each fire makes only the current block due,
    // then resolve() advances to the next block.

    /// Distinct block indices that actually have exercises, in cyclic order.
    private var blockOrder: [Int] { Array(Set(exercises.map { $0.block })).sorted() }

    /// Exercises firing next; normalizes currentBlock so it always lands on a real block.
    private func currentGroup() -> [Exercise] {
        let order = blockOrder
        guard !order.isEmpty else { return [] }
        if !order.contains(currentBlock) { currentBlock = order[0] }
        return exercises.filter { $0.block == currentBlock }
    }

    private func advanceBlock() {
        let order = blockOrder
        guard let i = order.firstIndex(of: currentBlock) else { currentBlock = order.first ?? 0; return }
        currentBlock = order[(i + 1) % order.count]
    }

    // View-facing (non-mutating — safe to read during SwiftUI body eval).
    var blockCount: Int { blockOrder.count }
    var currentBlockNumber: Int { (blockOrder.firstIndex(of: currentBlock) ?? 0) + 1 }
    var currentBlockNames: String {
        exercises.filter { $0.block == currentBlock }.map(\.name).joined(separator: ", ")
    }

    // MARK: - Internals

    private func beginRunning(seconds: TimeInterval, preserveTotal: Bool = false) {
        if !preserveTotal { runTotalSeconds = Int(seconds.rounded(.up)) }
        phase = .running(end: Date().addingTimeInterval(seconds))
        secondsLeft = Int(seconds.rounded(.up))
        scheduleNotification(after: seconds)
        beginActivity()
    }

    private func flashCompletion() {
        justCompletedRound = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.justCompletedRound = false
        }
    }

    private func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private func persist() {
        let state = PersistedState(intervalMinutes: intervalMinutes, exercises: exercises,
                                   lifetimeReps: lifetimeReps, lifetimeRounds: lifetimeRounds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: storeURL, options: .atomic)
        // ponytail: mirror every save to a second file so a lost or corrupted
        // state.json can't wipe lifetime totals. Same directory, so it won't
        // survive disk loss — add an offsite/timestamped snapshot if that matters.
        try? data.write(to: backupURL, options: .atomic)
    }

    // MARK: - Notifications
    // Scheduled in advance via a trigger so the system delivers on time even
    // if this process is napped or the Mac slept past the end date.

    private func requestAuthIfNeeded() {
        guard notificationsAvailable, !authRequested else { return }
        authRequested = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleNotification(after seconds: TimeInterval) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to move!"
        let group = currentGroup()   // runs after advanceBlock, so this is what fires next
        content.body = group.isEmpty
            ? "Time for a movement break."
            : group.map { "\($0.name) × \($0.targetReps)" }.joined(separator: "  ·  ")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }

    private func cancelPendingNotification() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    private func clearDeliveredNotifications() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - App Nap
    // Suppress App Nap while running so the tick stays honest and the icon
    // flips to "due" promptly (does not prevent system sleep).

    private func beginActivity() {
        endActivity()
        activity = ProcessInfo.processInfo
            .beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Workout interval timer")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
