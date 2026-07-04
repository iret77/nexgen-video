import SwiftUI

// The frames review gallery (docs/UI_UX_CONCEPT.md §4, ladder rung 2): per shot, the generated
// candidates as tiles with two structured decisions — Use (select as keyframe) and Redo with a
// reason chip + optional note. Both compose a structured agent command; the agent runs the pipeline
// work and the Agent tab opens to show it. Read-only against `read frames`; no state is invented.

struct ReviewPanelView: View {
    @Environment(EditorViewModel.self) private var editor

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded(FramesData?)
        case failed(CockpitError)
    }

    /// Reject reasons (concept §4) — a cheap structured "why", so a regeneration isn't a lottery.
    enum ReviewReason: String, CaseIterable, Identifiable {
        case continuity = "Continuity"
        case performance = "Performance"
        case style = "Style"
        case composition = "Composition"
        case promptDrift = "Prompt-Drift"
        case technical = "Technical"
        var id: String { rawValue }
    }

    private struct RedoTarget: Identifiable {
        let shotId: String
        let frameName: String
        var id: String { "\(shotId)/\(frameName)" }
    }

    @State private var state: LoadState = .idle
    @State private var loadToken = 0
    @State private var redoTarget: RedoTarget?
    @State private var redoReason: ReviewReason = .continuity
    @State private var redoNote = ""

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: editor.projectURL) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            VStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            CockpitStateView.error(error, title: "Couldn't load frames",
                                   subject: "the frames") { Task { await load() } }
        case .loaded(let data):
            if let data, !data.shots.isEmpty {
                loadedBody(data)
            } else {
                CockpitStateView.empty(icon: "photo.on.rectangle.angled", title: "Nothing to review",
                                       message: "The frames phase hasn't produced candidates yet.")
            }
        }
    }

    private func loadedBody(_ data: FramesData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                ForEach(data.shots) { shot in
                    shotSection(shot)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Shot section

    private func shotSection(_ shot: FrameShot) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    editor.inspectedObject = .shot(shot.shotId)
                } label: {
                    Text(shot.shotId)
                        .font(.system(size: AppTheme.FontSize.sm, weight: .semibold).monospaced())
                        .foregroundStyle(AppTheme.Text.primaryColor)
                }
                .buttonStyle(.plain)
                .help("Inspect this shot")
                if let status = shot.auditStatus, !status.isEmpty {
                    Text("audit: \(status)")
                        .font(.system(size: AppTheme.FontSize.xxs, weight: .medium))
                        .foregroundStyle(status == "pass" ? AppTheme.Status.successColor : AppTheme.Status.errorColor)
                }
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
                    ForEach(shot.frames) { frame in
                        frameTile(frame, shotId: shot.shotId)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.mdLg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(AppTheme.Background.raisedColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        )
    }

    private func frameTile(_ frame: FrameCandidate, shotId: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            SheetThumbnailView(
                label: frame.name,
                path: frame.path,
                projectDir: editor.studioProjectDir,
                tileHeight: 90
            )
            HStack(spacing: AppTheme.Spacing.xs) {
                Button("Use") { accept(frame, shotId: shotId) }
                    .controlSize(.small)
                Button("Redo…") {
                    redoReason = .continuity
                    redoNote = ""
                    redoTarget = RedoTarget(shotId: shotId, frameName: frame.name)
                }
                .controlSize(.small)
            }
        }
        .frame(width: 160)
        .popover(item: bindingRedoTarget(matching: frame, shotId: shotId)) { target in
            redoPopover(target)
        }
    }

    /// Per-tile popover anchoring: only the tile that opened the popover presents it.
    private func bindingRedoTarget(matching frame: FrameCandidate, shotId: String) -> Binding<RedoTarget?> {
        Binding(
            get: {
                guard let t = redoTarget, t.shotId == shotId, t.frameName == frame.name else { return nil }
                return t
            },
            set: { redoTarget = $0 }
        )
    }

    // MARK: - Decisions → structured agent commands

    private func redoPopover(_ target: RedoTarget) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text("Why regenerate?")
                .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: AppTheme.Spacing.xs) {
                ForEach(ReviewReason.allCases) { reason in
                    let selected = redoReason == reason
                    Button {
                        redoReason = reason
                    } label: {
                        Text(reason.rawValue)
                            .font(.system(size: AppTheme.FontSize.xs, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.xxs)
                            .background {
                                Capsule().fill(selected ? AppTheme.Background.surfaceColor : Color.clear)
                            }
                            .overlay(Capsule().strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("Optional note…", text: $redoNote)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: AppTheme.FontSize.sm))
            HStack {
                Spacer()
                Button("Regenerate") { regenerate(target) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.mdLg)
        .frame(width: 300)
    }

    private func accept(_ frame: FrameCandidate, shotId: String) {
        send("For shot \(shotId), use the frame candidate \u{201C}\(frame.name)\u{201D} as the selected keyframe.")
    }

    private func regenerate(_ target: RedoTarget) {
        let note = redoNote.trimmingCharacters(in: .whitespacesAndNewlines)
        var command = "Regenerate the keyframe for shot \(target.shotId) "
            + "(rejected candidate: \u{201C}\(target.frameName)\u{201D}). Reason: \(redoReason.rawValue)."
        if !note.isEmpty { command += " Note: \(note)" }
        redoTarget = nil
        send(command)
    }

    private func send(_ command: String) {
        editor.agentService.send(text: command, mentions: [])
        editor.agentPanelVisible = true
    }

    // MARK: - Load

    private func load() async {
        guard let dir = editor.studioProjectDir else {
            state = .failed(.noProject)
            return
        }
        loadToken += 1
        let token = loadToken
        state = .loading
        let result = await CockpitDataService.frames(projectDir: dir)
        guard token == loadToken else { return }
        switch result {
        case .success(let data): state = .loaded(data)
        case .failure(let error): state = .failed(error)
        }
    }
}
