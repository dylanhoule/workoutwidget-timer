import SwiftUI
import AppKit
import QuartzCore

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            if showSettings {
                SettingsSection(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                if model.phase == .due {
                    DueSection(model: model)
                        .transition(.asymmetric(
                            insertion: AnyTransition.scale(scale: 0.92).combined(with: .opacity)
                                .combined(with: .offset(y: 10)),
                            removal: .scale(scale: 1.04).combined(with: .opacity)))
                } else {
                    TimerSection(model: model)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .opacity))
                    QuickLogSection(model: model)
                }
                StatsSection(model: model)
            }
            HStack {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showSettings.toggle()
                    }
                } label: {
                    Image(systemName: showSettings ? "chevron.left" : "gearshape.fill")
                }
                .buttonStyle(QuietIconButtonStyle())
                .help(showSettings ? "Back" : "Settings")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(ThemeBackground())
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
                   value: model.phase)
        .onAppear { model.tick() }  // fresh countdown the moment the popover opens
        .onChange(of: model.justCompletedRound) { flashed in
            if flashed { NSSound(named: "Glass")?.play() }
        }
    }
}

// MARK: - Countdown (idle / running / paused)

struct TimerSection: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ProgressRing(progress: progress, mode: ringMode) {
                    VStack(spacing: 2) {
                        Text(model.countdownText)
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .foregroundColor(model.phase == .idle ? .textSecondary : .textPrimary)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.25),
                                       value: model.secondsLeft)
                        statusLine
                            .frame(height: 26)
                            .animation(.spring(response: 0.35, dampingFraction: 0.6),
                                       value: model.justCompletedRound)
                    }
                    .frame(width: 118)
                }
                if model.justCompletedRound && !reduceMotion {
                    CelebrationBurst()
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(model.justCompletedRound && !reduceMotion ? 1.05 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.45),
                       value: model.justCompletedRound)

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

    private var progress: Double {
        if case .idle = model.phase { return 1 }
        return Double(model.secondsLeft) / Double(max(1, model.runTotalSeconds))
    }

    private var ringMode: RingMode {
        switch model.phase {
        case .running: return .running
        case .paused: return .paused
        default: return .idle
        }
    }

    @ViewBuilder private var statusLine: some View {
        if model.justCompletedRound {
            Label("Round complete!", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient.energy)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        } else {
            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .transition(.opacity)
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
        .buttonStyle(EnergyPrimaryButtonStyle())
    }

    private var resetButton: some View {
        Button { model.reset() } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(QuietIconButtonStyle(size: 32))
        .help("Reset")
    }
}

// MARK: - Due checklist

struct DueSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient.energy))
                    .shadow(color: .glow.opacity(0.4), radius: 6, y: 2)
                Text("Time to move!")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
            }
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
                .transition(.scale(scale: 0.9).combined(with: .opacity))
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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text("target ×\(item.targetReps)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.textTertiary)
            }
            Spacer(minLength: 4)
            RepsControl(reps: $reps)
            Button("Log") { log(reps) }
                .buttonStyle(EnergyPrimaryButtonStyle(compact: true))
            Button(action: skip) {
                Image(systemName: "xmark")
            }
            .buttonStyle(QuietIconButtonStyle(size: 22))
            .help("Skip (logs nothing)")
        }
        .card()
    }
}

// MARK: - Off-time logging

/// Log reps done outside a scheduled round. The stat numbers tick up on Log,
/// so no separate confirmation is needed.
struct QuickLogSection: View {
    @ObservedObject var model: AppModel
    @State private var selectedName = ""
    @State private var reps = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("QUICK LOG")
            HStack(spacing: 6) {
                Picker("", selection: $selectedName) {
                    ForEach(model.exercises) { ex in Text(ex.name).tag(ex.name) }
                }
                .labelsHidden()
                Spacer(minLength: 0)
                RepsControl(reps: $reps)
                Button("Log") { model.logManual(name: selectedName, reps: reps) }
                    .buttonStyle(EnergyPrimaryButtonStyle(compact: true))
                    .disabled(selectedName.isEmpty)
            }
        }
        .card(padding: 12)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("SESSION")
                Spacer()
                Button("Reset session") { model.resetSession() }
                    .buttonStyle(QuietButtonStyle())
            }
            ForEach(model.exercises) { ex in
                statRow(ex)
            }
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LinearGradient.energy)
                    Text("\(model.sessionRounds) round\(model.sessionRounds == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.textPrimary)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Capsule().fill(LinearGradient.energy).opacity(0.18))
                Text("\(model.lifetimeRounds) all-time")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.textTertiary)
                Spacer()
            }
        }
        .card(padding: 12)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.sessionReps)
    }

    private func statRow(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ex.name)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(model.sessionCount(for: ex.name))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.textPrimary)
                    .contentTransition(.numericText())
                Text("\(model.lifetimeCount(for: ex.name)) all-time")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.textTertiary)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            // Session bar, relative to the session leader (min 1 so all-zero → empty).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(LinearGradient.energy)
                        .frame(width: barWidth(for: ex, in: geo.size.width))
                }
            }
            .frame(height: 4)
        }
    }

    private func barWidth(for ex: Exercise, in trackWidth: CGFloat) -> CGFloat {
        let count = model.sessionCount(for: ex.name)
        guard count > 0 else { return 0 }
        let leader = max(1, model.exercises.map { model.sessionCount(for: $0.name) }.max() ?? 1)
        return max(4, trackWidth * CGFloat(count) / CGFloat(leader))
    }
}

// MARK: - Due panel (always-on-top reminder)

/// Root of the floating panel: DueSection on the app background, in a rounded
/// card. Kept as a plain wrapper so the popover and panel share DueSection.
private struct DuePanelRoot: View {
    let model: AppModel

    var body: some View {
        DueSection(model: model)
            .padding(16)
            .frame(width: 320)
            .background(ThemeBackground())
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.cardEdge, lineWidth: 1))
            .preferredColorScheme(.dark)
    }
}

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
            p.isOpaque = false                                    // rounded dark card
            p.backgroundColor = .clear
            p.appearance = NSAppearance(named: .darkAqua)
            [.closeButton, .miniaturizeButton, .zoomButton].forEach {
                p.standardWindowButton($0)?.isHidden = true       // no manual dismiss
            }
            p.contentViewController = NSHostingController(
                rootView: DuePanelRoot(model: model))
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
        let animateIn = !panel.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let finalFrame = panel.frame
        if animateIn {
            panel.setFrame(finalFrame.offsetBy(dx: 0, dy: 14), display: false)
            panel.alphaValue = 0
        }
        NSApp.activate(ignoringOtherApps: true)                   // steal focus — invasive on purpose
        panel.makeKeyAndOrderFront(nil)
        if animateIn {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalFrame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
    }

    func hide() { panel?.orderOut(nil) }
}

// MARK: - Settings

struct SettingsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Remind every")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.textPrimary)
                    TextField("", value: $model.intervalMinutes, format: .number)
                        .darkField()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48)
                    Stepper("", value: $model.intervalMinutes, in: 1...480)
                        .labelsHidden()
                    Text("min")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                Text("Applies when the timer next starts.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.textTertiary)
            }
            .card(padding: 12)

            SectionHeader("EXERCISES")
            // ponytail: exercise CRUD locked while a round is due — deletes every
            // "edited mid-checklist" reconcile edge case
            Group {
                ForEach($model.exercises) { $ex in
                    HStack(spacing: 6) {
                        TextField("Name", text: $ex.name)
                            .darkField()
                        TextField("", value: $ex.targetReps, format: .number)
                            .darkField()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 40)
                        Stepper("B\(ex.block + 1)", value: $ex.block, in: 0...max(1, model.blockCount))
                            .fixedSize()
                            .font(.system(size: 11, design: .rounded))
                            .help("Rotation block")
                        Button { model.removeExercise(ex.id) } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(QuietIconButtonStyle(size: 22))
                        .help("Remove")
                    }
                    .card(padding: 8)
                }
                HStack(spacing: 8) {
                    Button { model.addExercise() } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    .buttonStyle(QuietButtonStyle())
                    Button { model.addBlock() } label: {
                        Label("Add block", systemImage: "square.stack.3d.up")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .disabled(model.phase == .due)

            if model.phase == .due {
                Text("Finish or skip this round before editing exercises.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.textTertiary)
            }
        }
    }
}
