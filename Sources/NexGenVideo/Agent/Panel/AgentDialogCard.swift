import SwiftUI

/// The composer-dock rendering of a pending `AgentDialog` (locked placement architecture, #96):
/// a native card docked ABOVE the input — the input itself becomes the dialog-scoped free text.
/// Submit composes ONE structured message back to the agent (the transcript record), Esc/X cancels.
struct AgentDialogCard: View {
    let dialog: AgentDialog
    @Environment(EditorViewModel.self) private var editor

    /// Selection state per section id. Choices hold selected option ids; toggles hold "on".
    @State private var choiceSelections: [String: Set<String>] = [:]
    @State private var toggleStates: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            header
            if let intro = dialog.intro {
                Text(intro)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(dialog.sections) { section in
                sectionView(section)
            }
            footerRow
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Background.raisedColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Accent.primary.opacity(AppTheme.Opacity.medium),
                              lineWidth: AppTheme.BorderWidth.thin)
        )
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .onAppear(perform: seedDefaults)
        .id(dialog.id)
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: dialog.symbol)
                .font(.system(size: AppTheme.FontSize.md))
                .foregroundStyle(AppTheme.Accent.primary)
            Text(dialog.title)
                .font(.system(size: AppTheme.FontSize.smMd, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Spacer(minLength: AppTheme.Spacing.sm)
            Button {
                editor.agentService.cancelDialog()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Dismiss (Esc)")
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AgentDialog.Section) -> some View {
        switch section.kind {
        case .choices(let options, let multiSelect):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(section.label.uppercased())
                    .font(.system(size: AppTheme.FontSize.xxs, weight: .semibold))
                    .tracking(AppTheme.Tracking.wide)
                    .foregroundStyle(AppTheme.Text.mutedColor)
                FlowChips(options: options,
                          selected: choiceSelections[section.id] ?? [],
                          multiSelect: multiSelect) { optionId in
                    toggleChoice(sectionId: section.id, optionId: optionId, multiSelect: multiSelect)
                }
            }
        case .toggle:
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(section.label)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { toggleStates[section.id] ?? false },
                    set: { toggleStates[section.id] = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let cost = dialog.costHint {
                Text(cost)
                    .font(.system(size: AppTheme.FontSize.xxs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }
            Spacer()
            Button(dialog.confirmLabel) { submit() }
                .buttonStyle(.capsule(.prominent, size: .regular))
                .controlSize(.small)
        }
    }

    // MARK: - State

    private func seedDefaults() {
        for section in dialog.sections {
            if case .toggle(let defaultOn) = section.kind, toggleStates[section.id] == nil {
                toggleStates[section.id] = defaultOn
            }
        }
    }

    private func toggleChoice(sectionId: String, optionId: String, multiSelect: Bool) {
        var current = choiceSelections[sectionId] ?? []
        if multiSelect {
            if current.contains(optionId) { current.remove(optionId) } else { current.insert(optionId) }
        } else {
            current = current.contains(optionId) ? [] : [optionId]
        }
        choiceSelections[sectionId] = current
    }

    /// Compose the ONE structured answer message — the compact transcript record the locked
    /// architecture calls for — and hand it (plus the dialog-scoped free text) back to the agent.
    private func submit() {
        var parts: [String] = []
        for section in dialog.sections {
            switch section.kind {
            case .choices(let options, _):
                let picked = options.filter { (choiceSelections[section.id] ?? []).contains($0.id) }
                if !picked.isEmpty {
                    parts.append("\(section.label): \(picked.map(\.label).joined(separator: ", "))")
                }
            case .toggle:
                parts.append("\(section.label): \((toggleStates[section.id] ?? false) ? "yes" : "no")")
            }
        }
        editor.agentService.submitDialog(title: dialog.title, answers: parts)
    }
}

/// Wrapping chip rows for choice options — compact controls only; rich visual picking belongs to
/// the canonical surfaces (canvas projection), not this card.
private struct FlowChips: View {
    let options: [AgentDialog.Choice]
    let selected: Set<String>
    let multiSelect: Bool
    let onTap: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: AppTheme.Spacing.xs)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.xs) {
            ForEach(options) { option in
                let isOn = selected.contains(option.id)
                Button {
                    onTap(option.id)
                } label: {
                    HStack(spacing: AppTheme.Spacing.xxs) {
                        if let symbol = option.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: AppTheme.FontSize.xxs))
                        }
                        Text(option.label)
                            .font(.system(size: AppTheme.FontSize.xs,
                                          weight: isOn ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xxs)
                    .foregroundStyle(isOn ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
                    .background(
                        Capsule().fill(isOn
                                       ? AppTheme.Accent.primary.opacity(AppTheme.Opacity.faint)
                                       : Color.white.opacity(AppTheme.Opacity.subtle))
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            isOn ? AppTheme.Accent.primary : AppTheme.Border.subtleColor,
                            lineWidth: AppTheme.BorderWidth.hairline)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
