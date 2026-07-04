import SwiftUI
import AppKit

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 12) {
            if showSettings {
                SettingsSection(model: model)
            } else {
                if model.phase == .due {
                    DueSection(model: model)
                } else {
                    TimerSection(model: model)
                    Divider()
                    QuickLogSection(model: model)
                }
                Divider()
                StatsSection(model: model)
            }
            Divider()
            HStack {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: showSettings ? "chevron.left" : "gearshape")
                }
                .buttonStyle(.borderless)
                .help(showSettings ? "Back" : "Settings")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.tick() }  // fresh countdown the moment the popover opens
        .onChange(of: model.justCompletedRound) { flashed in
            if flashed { NSSound(named: "Glass")?.play() }
        }
    }
}

// MARK: - Countdown (idle / running / paused)

struct TimerSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            Text(model.countdownText)
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(model.phase == .idle ? .secondary : .primary)

            Group {
                if model.justCompletedRound {
                    Label("Round complete!", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 18)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: model.justCompletedRound)

            HStack(spacing: 8) {
                switch model.phase {
                case .idle:
                    primaryButton("Start", icon: "play.fill") { model.start() }
                        .keyboardShortcut(.defaultAction)
                case .running:
                    primaryButton("Pause", icon: "pause.fill") { model.pause() }
                    resetButton
                case .paused:
                    primaryButton("Resume", icon: "play.fill") { model.resume() }
                        .keyboardShortcut(.defaultAction)
                    resetButton
                case .due:
                    EmptyView()
                }
            }
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .idle:
            return "every \(model.intervalMinutes) min"
        case .running(let end):
            let t = end.formatted(date: .omitted, time: .shortened)
            return model.blockCount > 1
                ? "block \(model.currentBlockNumber): \(model.currentBlockNames) · \(t)"
                : "next round at \(t)"
        case .paused:
            return "paused"
        case .due:
            return ""
        }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var resetButton: some View {
        Button { model.reset() } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("Reset")
    }
}

// MARK: - Due checklist

struct DueSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Time to move!", systemImage: "figure.run")
                .font(.headline)
            ForEach(model.dueItems) { item in
                DueRow(item: item,
                       log: { reps in
                           withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                               model.log(id: item.id, reps: reps)
                           }
                       },
                       skip: {
                           withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                               model.skip(id: item.id)
                           }
                       })
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
    }
}

struct DueRow: View {
    let item: DueItem
    let log: (Int) -> Void
    let skip: () -> Void
    @State private var reps: Int

    init(item: DueItem, log: @escaping (Int) -> Void, skip: @escaping () -> Void) {
        self.item = item
        self.log = log
        self.skip = skip
        _reps = State(initialValue: item.targetReps)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(item.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            TextField("", value: $reps, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Stepper("", value: $reps, in: 0...999)
                .labelsHidden()
            Button("Log") { log(reps) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(action: skip) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Skip (logs nothing)")
        }
    }
}

// MARK: - Off-time logging

/// Log reps done outside a scheduled round. The Session/Lifetime numbers in
/// StatsSection tick up on Log, so no separate confirmation is needed.
struct QuickLogSection: View {
    @ObservedObject var model: AppModel
    @State private var selectedName = ""
    @State private var reps = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOG OFF-TIME")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Picker("", selection: $selectedName) {
                    ForEach(model.exercises) { ex in Text(ex.name).tag(ex.name) }
                }
                .labelsHidden()
                TextField("", value: $reps, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Stepper("", value: $reps, in: 0...999).labelsHidden()
                Button("Log") { model.logManual(name: selectedName, reps: reps) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedName.isEmpty)
            }
        }
        // ponytail: default to first exercise; if the selected name was renamed/
        // removed, fall back so the picker never sits on a stale value.
        .onAppear { fixSelection() }
        .onChange(of: model.exercises) { _ in fixSelection() }
    }

    private func fixSelection() {
        if !model.exercises.contains(where: { $0.name == selectedName }) {
            selectedName = model.exercises.first?.name ?? ""
        }
    }
}

// MARK: - Stats

struct StatsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STATS")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Reset session") { model.resetSession() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    Text("Session").gridColumnAlignment(.trailing)
                    Text("Lifetime").gridColumnAlignment(.trailing)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                ForEach(model.exercises) { ex in
                    GridRow {
                        Text(ex.name).lineLimit(1)
                        Text("\(model.sessionCount(for: ex.name))").monospacedDigit()
                        Text("\(model.lifetimeCount(for: ex.name))").monospacedDigit()
                    }
                    .font(.callout)
                }
                Divider()
                GridRow {
                    Text("Rounds")
                    Text("\(model.sessionRounds)").monospacedDigit()
                    Text("\(model.lifetimeRounds)").monospacedDigit()
                }
                .font(.callout)
            }
        }
    }
}

// MARK: - Due panel (always-on-top reminder)

/// Always-on-top checklist that appears when a round is due and stays until
/// every exercise is logged or skipped. This is the "unignorable" reminder;
/// the system banner is only a secondary nudge.
final class DuePanelController {
    private var panel: NSPanel?

    func show(model: AppModel) {
        if panel == nil {
            let p = NSPanel(contentRect: .zero,
                            styleMask: [.titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.level = .floating                                   // above normal windows
            // .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive —
            // setting both throws NSInternalInconsistencyException. Keep the
            // "visible on every space" behavior; drop the conflicting flag.
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.isFloatingPanel = true
            [.closeButton, .miniaturizeButton, .zoomButton].forEach {
                p.standardWindowButton($0)?.isHidden = true       // no manual dismiss
            }
            p.contentViewController = NSHostingController(
                rootView: DueSection(model: model).padding(16).frame(width: 320))
            panel = p
        }
        guard let panel else { return }
        // ponytail: a titled NSPanel won't auto-size to its SwiftUI content, so
        // size it to the hosting view's fittingSize on every show (keeps it correct
        // if the exercise count changed). Without this the window stays ~zero-size
        // and the panel appears empty / not at all.
        if let host = panel.contentViewController {
            host.view.layoutSubtreeIfNeeded()
            panel.setContentSize(host.view.fittingSize)
        }
        if let screen = NSScreen.main {                           // top-center of main screen
            let f = panel.frame, vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - f.width / 2,
                                         y: vf.maxY - f.height - 24))
        }
        NSApp.activate(ignoringOtherApps: true)                   // steal focus — invasive on purpose
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
}

// MARK: - Settings

struct SettingsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.headline)

            HStack(spacing: 6) {
                Text("Remind every")
                TextField("", value: $model.intervalMinutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                Stepper("", value: $model.intervalMinutes, in: 1...480)
                    .labelsHidden()
                Text("min")
            }
            Text("Applies when the timer next starts.")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            Text("EXERCISES")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            // ponytail: exercise CRUD locked while a round is due — deletes every
            // "edited mid-checklist" reconcile edge case
            Group {
                ForEach($model.exercises) { $ex in
                    HStack(spacing: 6) {
                        TextField("Name", text: $ex.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("", value: $ex.targetReps, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 44)
                        Stepper("B\(ex.block + 1)", value: $ex.block, in: 0...max(1, model.blockCount))
                            .fixedSize()
                            .help("Rotation block")
                        Button { model.removeExercise(ex.id) } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
                HStack(spacing: 12) {
                    Button { model.addExercise() } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    Button { model.addBlock() } label: {
                        Label("Add block", systemImage: "square.stack.3d.up")
                    }
                }
                .buttonStyle(.borderless)
            }
            .disabled(model.phase == .due)

            if model.phase == .due {
                Text("Finish or skip this round before editing exercises.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
