import SwiftUI

// Shared loading / empty / error / engine-not-ready state views for the cockpit panels, factored out
// of the Bible panel's idiom so Pipeline / Shotlist / Sanity / Cost render identical states. Read-only.

enum CockpitStateView {

    /// Error / engine-not-ready state. `subject` fills the "Set up the engine to view the <subject>."
    /// copy when the engine isn't ready.
    static func error(
        _ error: CockpitError,
        title: String,
        subject: String,
        retry: @escaping () -> Void
    ) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: error == .engineNotReady ? "gearshape" : "exclamationmark.triangle")
                .font(.system(size: AppTheme.FontSize.title1))
                .foregroundStyle(AppTheme.Text.mutedColor)
            Text(error == .engineNotReady ? "Engine not set up" : title)
                .font(.system(size: AppTheme.FontSize.md, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            Text(error == .engineNotReady
                 ? "Set up the engine in Settings to view \(subject)."
                 : error.message)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.mutedColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry)
                .buttonStyle(.plain)
                .font(.system(size: AppTheme.FontSize.sm, weight: .medium))
                .foregroundStyle(AppTheme.Accent.primary)
                .padding(.top, AppTheme.Spacing.xs)
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Empty / placeholder state.
    static func empty(icon: String, title: String, message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: AppTheme.FontSize.title1))
                .foregroundStyle(AppTheme.Text.mutedColor)
            Text(title)
                .font(.system(size: AppTheme.FontSize.md, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            Text(message)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.mutedColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
