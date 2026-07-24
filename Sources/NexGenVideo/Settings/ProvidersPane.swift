import AppKit
import SwiftUI

struct ProvidersPane: View {
    @State private var hasKey: [String: Bool] = [:]
    @State private var maskedKey: [String: String] = [:]
    @State private var draft: [String: String] = [:]
    @State private var oauthConnected: [String: Bool] = [:]
    @State private var localEnabled: [String: Bool] = [:]
    @State private var signingIn: String?
    @State private var errorText: [String: String] = [:]
    @State private var oauth = ProviderOAuth()
    @FocusState private var focusedProvider: String?

    @AppStorage(PromptCompiler.rawPromptsDefaultsKey) private var allowRawPrompts = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            SettingsSection(
                "Connected Services",
                subtitle: "Credentials are stored in the macOS Keychain. Each provider shows only its supported connection method."
            ) {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: AppTheme.ComponentSize.settingsProviderCardMinWidth),
                            spacing: AppTheme.Spacing.smMd
                        ),
                    ],
                    alignment: .leading,
                    spacing: AppTheme.Spacing.smMd
                ) {
                    ForEach(GenerationProvider.allCases) { provider in
                        providerSection(provider)
                    }
                }
            }
            SettingsSection("Prompt Processing") {
                SettingsCard {
                    SettingsToggleRow(
                        title: "Allow raw prompts",
                        subtitle: "Send text directly to generation models without NexGenVideo's translation, context, or consistency passes.",
                        isOn: $allowRawPrompts
                    )
                    if allowRawPrompts {
                        SettingsDivider()
                        SettingsNotice(
                            text: "Prompt safeguards are bypassed for raw generation requests.",
                            systemImage: "exclamationmark.triangle",
                            tone: .warning
                        )
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private func providerSection(_ provider: GenerationProvider) -> some View {
        SettingsCard {
            providerHeader(provider)
                .padding(.horizontal, AppTheme.Spacing.mdLg)
                .padding(.vertical, AppTheme.Spacing.md)
            SettingsDivider()
            switch primaryStyle(provider) {
            case .oauth: oauthControl(provider)
            case .localApp: localAppControl(provider)
            case .apiKey: keyField(provider)
            }
            if let err = errorText[provider.id] {
                SettingsDivider()
                SettingsNotice(text: err, systemImage: "exclamationmark.triangle", tone: .error)
            }
        }
    }

    private enum Style { case oauth, localApp, apiKey }
    private func primaryStyle(_ p: GenerationProvider) -> Style {
        switch p.mcpCapability?.auth {
        case .oauth: return .oauth
        case .localApp: return .localApp
        case .none: return .apiKey
        }
    }

    private func isReady(_ p: GenerationProvider) -> Bool {
        switch primaryStyle(p) {
        case .oauth: return oauthConnected[p.id] == true
        case .localApp: return localEnabled[p.id] == true
        case .apiKey: return hasKey[p.id] == true
        }
    }

    private func providerHeader(_ provider: GenerationProvider) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(provider.displayName)
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    Text(provider.modalities)
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if primaryStyle(provider) != .localApp {
                        linkButton(provider)
                    }
                }
            }
            Spacer(minLength: AppTheme.Spacing.md)
            statusPill(provider)
        }
    }

    private func linkButton(_ provider: GenerationProvider) -> some View {
        Button(action: { NSWorkspace.shared.open(provider.keysURL) }) {
            HStack(spacing: AppTheme.Spacing.xxs) {
                Text(primaryStyle(provider) == .oauth ? "Website" : "Get key")
                Image(systemName: "arrow.up.right").font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
            }
            .font(.system(size: AppTheme.FontSize.sm))
            .foregroundStyle(AppTheme.Accent.primary)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func statusPill(_ provider: GenerationProvider) -> some View {
        let ready = isReady(provider)
        let label: String
        switch primaryStyle(provider) {
        case .oauth: label = ready ? "Signed in" : "Not configured"
        case .localApp: label = ready ? "Enabled" : "Disabled"
        case .apiKey: label = ready ? "Key saved" : "Not configured"
        }
        return SettingsStatusBadge(text: label, tone: ready ? .success : .neutral)
    }

    @ViewBuilder
    private func oauthControl(_ provider: GenerationProvider) -> some View {
        let connected = oauthConnected[provider.id] == true
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if let note = provider.mcpCapability?.note {
                Text(note).font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                if connected {
                    Label("Signed in", systemImage: "checkmark.seal.fill")
                        .font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Accent.primary)
                    Button("Sign out") { ProviderOAuthStore.disconnect(provider); refresh() }
                        .buttonStyle(.capsule(.secondary, size: .regular))
                } else if signingIn == provider.id {
                    ProgressView().controlSize(.small)
                    Text("Opening \(provider.displayName)…").font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.tertiaryColor)
                } else {
                    Button("Sign in with \(provider.displayName)") { signIn(provider) }
                        .buttonStyle(.capsule(.prominent, size: .regular))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    @ViewBuilder
    private func localAppControl(_ provider: GenerationProvider) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(provider.mcpCapability?.note ?? "")
                    .font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AppTheme.Spacing.lg)
            Toggle("", isOn: Binding(
                get: { localEnabled[provider.id] == true },
                set: { on in
                    ProviderMCP.setEndpoint(on ? provider.mcpCapability?.defaultURL.absoluteString : nil, for: provider)
                    refresh()
                }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private func keyField(_ provider: GenerationProvider) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.sm) {
                SecureField(placeholder(provider), text: draftBinding(provider))
                    .textFieldStyle(.plain)
                    .focused($focusedProvider, equals: provider.id)
                    .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .onSubmit { save(provider) }
                    .padding(.horizontal, AppTheme.Spacing.md).padding(.vertical, AppTheme.Spacing.smMd)
                    .background(RoundedRectangle(cornerRadius: AppTheme.Radius.sm).fill(AppTheme.Background.overlayColor.opacity(AppTheme.Opacity.muted)))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.sm).strokeBorder(
                        focusedProvider == provider.id ? AppTheme.Border.primaryColor : AppTheme.Border.subtleColor,
                        lineWidth: AppTheme.BorderWidth.thin))
                trailingControl(provider)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    @ViewBuilder
    private func trailingControl(_ provider: GenerationProvider) -> some View {
        let trimmed = (draft[provider.id] ?? "").trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            Button("Save") { save(provider) }.buttonStyle(.capsule(.prominent, size: .regular)).controlSize(.large)
        } else if hasKey[provider.id] == true {
            Button(action: { remove(provider) }) {
                Image(systemName: "trash").font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
            }
            .buttonStyle(.capsule(.secondary, size: .regular)).controlSize(.large)
            .help("Remove \(provider.displayName) API key")
        }
    }

    private func signIn(_ provider: GenerationProvider) {
        signingIn = provider.id
        errorText[provider.id] = nil
        Task {
            do { try await oauth.signIn(provider) }
            catch { errorText[provider.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            signingIn = nil
            refresh()
        }
    }

    private func placeholder(_ provider: GenerationProvider) -> String {
        hasKey[provider.id] == true ? (maskedKey[provider.id] ?? "") : "Paste API key…"
    }

    private func draftBinding(_ provider: GenerationProvider) -> Binding<String> {
        Binding(get: { draft[provider.id] ?? "" }, set: { draft[provider.id] = $0 })
    }

    private func refresh() {
        for provider in GenerationProvider.allCases {
            let key = ProviderKeychain.load(provider) ?? ""
            hasKey[provider.id] = !key.isEmpty
            maskedKey[provider.id] = mask(key)
            oauthConnected[provider.id] = ProviderOAuthStore.isConnected(provider)
            localEnabled[provider.id] = ProviderMCP.configuredEndpoint(provider) != nil
        }
    }

    private func save(_ provider: GenerationProvider) {
        let key = (draft[provider.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        ProviderKeychain.save(key, for: provider)
        draft[provider.id] = ""
        focusedProvider = nil
        refresh()
    }

    private func remove(_ provider: GenerationProvider) {
        ProviderKeychain.delete(provider)
        draft[provider.id] = ""
        refresh()
    }

    private func mask(_ key: String) -> String {
        guard key.count > 4 else { return String(repeating: "\u{2022}", count: 32) }
        return String(repeating: "\u{2022}", count: 36) + key.suffix(4)
    }
}
