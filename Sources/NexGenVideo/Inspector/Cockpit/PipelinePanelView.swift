import SwiftUI

// Read-only Pipeline cockpit panel: the project's phase gates as a vertical checklist, with the next
// open phase highlighted — "where does the project stand". Loaded via CockpitDataService.projectState.
// Explicit loading / empty / error / engine-not-ready states. No mutations.

struct PipelinePanelView: View {
    @Environment(EditorViewModel.self) private var editor

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded(ProjectStateData?)
        case failed(CockpitError)
    }

    @State private var state: LoadState = .idle
    /// Guards against a stale reload result overwriting a newer one when the project changes mid-flight.
    @State private var loadToken = 0

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
            centeredProgress()
        case .failed(let error):
            CockpitStateView.error(error, title: "Couldn't load the pipeline",
                                   subject: "the pipeline") { Task { await load() } }
        case .loaded(nil):
            CockpitStateView.empty(icon: "list.bullet.rectangle", title: "No pipeline yet",
                                   message: "This project has no phase state.")
        case .loaded(.some(let data)):
            loadedBody(data)
        }
    }

    @ViewBuilder
    private func loadedBody(_ data: ProjectStateData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                summaryHeader(data)
                if data.phases.isEmpty {
                    CockpitStateView.empty(icon: "list.bullet.rectangle", title: "No phases",
                                           message: "This project has no defined phases.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(data.phases.enumerated()), id: \.element.id) { index, phase in
                            phaseRow(phase, isNext: phase.phase == data.nextPhaseName,
                                     isLast: index == data.phases.count - 1)
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
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryHeader(_ data: ProjectStateData) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            let approved = data.phases.filter(\.approved).count
            Text(data.isComplete ? "All phases complete" : "\(approved) of \(data.phases.count) phases approved")
                .font(.system(size: AppTheme.FontSize.md, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            if let next = data.nextPhaseName, !data.isComplete {
                Text("Next: \(next)")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Accent.timecodeColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phaseRow(_ phase: ProjectPhase, isNext: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.smMd) {
                statusDot(approved: phase.approved, isNext: isNext)
                Text(phase.phase)
                    .font(.system(size: AppTheme.FontSize.sm,
                                  weight: isNext ? .semibold : (phase.approved ? .regular : .medium)))
                    .foregroundStyle(phase.approved ? AppTheme.Text.tertiaryColor
                                     : (isNext ? AppTheme.Text.primaryColor : AppTheme.Text.secondaryColor))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if isNext {
                    Text("NEXT")
                        .font(.system(size: AppTheme.FontSize.micro, weight: .bold))
                        .tracking(AppTheme.Tracking.wide)
                        .foregroundStyle(AppTheme.Accent.timecodeColor)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                                .fill(AppTheme.Accent.timecodeColor.opacity(AppTheme.Opacity.faint))
                        )
                } else if phase.approved {
                    Text("Approved")
                        .font(.system(size: AppTheme.FontSize.xxs, weight: .medium))
                        .foregroundStyle(AppTheme.Status.successColor)
                }
            }
            .frame(height: AppTheme.IconSize.md)
            if !isLast {
                Divider().overlay(AppTheme.Border.subtleColor)
            }
        }
    }

    private func statusDot(approved: Bool, isNext: Bool) -> some View {
        Group {
            if approved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.Status.successColor)
            } else if isNext {
                Image(systemName: "circle.dashed.inset.filled")
                    .foregroundStyle(AppTheme.Accent.timecodeColor)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }
        }
        .font(.system(size: AppTheme.FontSize.md))
        .frame(width: AppTheme.IconSize.xs)
    }

    private func centeredProgress() -> some View {
        VStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard let dir = editor.studioProjectDir else {
            state = .failed(.noProject)
            return
        }
        loadToken += 1
        let token = loadToken
        state = .loading
        let result = await CockpitDataService.projectState(projectDir: dir)
        guard token == loadToken else { return }
        switch result {
        case .success(let data): state = .loaded(data)
        case .failure(let error): state = .failed(error)
        }
    }
}
