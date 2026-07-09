import AppKit
import SwiftUI

/// The window chrome row. The project window hides the system title and extends content beneath a
/// transparent titlebar (the FCP dark-room pattern — no standard toolbar chrome), and this view owns
/// that row: brand + project identity leading, the `Produce · Edit · Finish` stage toggle centered,
/// the active-plugin chip (click → plugin picker) and pipeline health trailing. Window-level facts
/// live here; panel navigation stays in the sidebar; object context stays in the Inspector
/// breadcrumb — three roles, three kinds of chrome (docs/UI_UX_CONCEPT.md §3).
struct TitleBarView: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var showsPluginPicker = false

    var body: some View {
        ZStack {
            HStack(spacing: AppTheme.Spacing.md) {
                projectName
                Spacer(minLength: AppTheme.Spacing.md)
                pluginChip
                healthCapsule
            }
            focusToggle
        }
        .sheet(isPresented: $showsPluginPicker) {
            PluginPickerView(editor: editor)
        }
        .padding(.leading, Layout.trafficLightInset)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.titleBarChromeHeight)
        .background(
            // Double-click the bare titlebar to zoom the window (macOS convention). It's a
            // background layer, so the buttons on top take their clicks first — only empty
            // titlebar area double-clicks zoom.
            Rectangle()
                .fill(AppTheme.Background.raisedColor)
                .onTapGesture(count: 2) { NSApp.keyWindow?.zoom(nil) }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.Border.primaryColor).frame(height: AppTheme.BorderWidth.hairline)
        }
        .task(id: editor.projectURL) { await editor.refreshEngineState() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Re-read on window activation so gate approvals / engine runs done elsewhere show up.
            Task { await editor.refreshEngineState() }
        }
    }

    /// Quiet brand lockup: the wordmark muted and regular, the project name emphasized. Mac-tasteful
    /// (name is the loud element), never the Windows "App - Doc" style. Wordmark is one word.
    private var projectName: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text("NexGenVideo")
                .font(.system(size: AppTheme.FontSize.xs, weight: .regular))
                .foregroundStyle(AppTheme.Text.mutedColor)
                .fixedSize()
            Text(editor.projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
                .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Focus toggle (centered — the window-level mode switch)

    private var focusToggle: some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            ForEach(EditorViewModel.WorkspaceFocus.allCases, id: \.self) { focus in
                let selected = editor.workspaceFocus == focus
                Button {
                    withAnimation(.easeInOut(duration: AppTheme.Anim.transition)) {
                        editor.setWorkspaceFocus(focus)
                    }
                } label: {
                    Text(focus.label)
                        .font(.system(size: AppTheme.FontSize.xs, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.xxs)
                        .background {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                                .fill(selected ? AppTheme.Background.surfaceColor : Color.clear)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.Spacing.xxs)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm).fill(AppTheme.Background.baseColor)
        }
    }

    // MARK: - Pipeline health capsule (absent when the project has no pipeline)

    /// The Format-plugin control — the editor's one entry into the pack gallery AND the workspace's
    /// active-format identity (Epic #98 / #95 C4). Format packs are the core feature, so this reads
    /// as a labelled, tappable control rather than a bare name: "Format" names the field, the value
    /// is the active pack (or "Generic"). When a pack is bound the pill takes an accent tint and
    /// border — active presence, so the chrome visibly reflects the running format.
    private var pluginChip: some View {
        let active = editor.activePluginName != nil
        return Button {
            showsPluginPicker = true
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(active ? AppTheme.Accent.primary : AppTheme.Text.tertiaryColor)
                Text("Format")
                    .font(.system(size: AppTheme.FontSize.xxs, weight: .medium))
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .fixedSize()
                Text(activePluginLabel)
                    .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
                    .foregroundStyle(active ? AppTheme.Accent.primary : AppTheme.Text.secondaryColor)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: AppTheme.FontSize.micro, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }
            .padding(.horizontal, AppTheme.Spacing.smMd)
            .padding(.vertical, AppTheme.Spacing.xxs)
            .background(
                Capsule().fill(active
                               ? AppTheme.Accent.primary.opacity(AppTheme.Opacity.faint)
                               : Color.white.opacity(AppTheme.Opacity.subtle))
            )
            .overlay(
                Capsule().strokeBorder(active
                                       ? AppTheme.Accent.primary.opacity(AppTheme.Opacity.moderate)
                                       : Color.white.opacity(AppTheme.Opacity.faint),
                                       lineWidth: AppTheme.BorderWidth.hairline)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(active
              ? "Active format plugin. Click to browse or change formats."
              : "Generic production workflow. Click to browse format plugins.")
    }

    private var activePluginLabel: String {
        guard let active = editor.activePluginName else { return "Generic" }
        return InstalledPack.named(active)?.displayName ?? active
    }

    @ViewBuilder
    private var healthCapsule: some View {
        if let state = editor.projectState {
            Button {
                editor.revealCockpit(.pipeline)
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: state.isComplete ? "checkmark.seal.fill" : "circle.dotted")
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(state.isComplete ? AppTheme.Accent.primary : AppTheme.Text.tertiaryColor)
                    Text(healthText(state))
                        .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                        .lineLimit(1)
                    if state.budgetEur > 0 {
                        Text(String(format: "€%.0f/%.0f", state.budgetSpentEur, state.budgetEur))
                            .font(.system(size: AppTheme.FontSize.xs, weight: .medium).monospacedDigit())
                            .foregroundStyle(state.budgetWarning ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.smMd)
                .padding(.vertical, AppTheme.Spacing.xxs)
                .background {
                    Capsule().fill(AppTheme.Background.baseColor)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Pipeline status — click to open")
        }
    }

    private func healthText(_ state: ProjectStateData) -> String {
        let approved = state.phases.filter(\.approved).count
        let total = state.phases.count
        if state.isComplete { return "Complete" }
        if let next = state.nextPhaseName { return "\(Self.phaseLabel(next)) · \(approved)/\(total)" }
        return "\(approved)/\(total)"
    }

    /// User-facing label for a phase id — the internal ids are snake_case (`project_init`), which must
    /// never reach the UI as raw debug text. Generic (works for pack phases too): underscores → spaces,
    /// title-cased.
    static func phaseLabel(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
