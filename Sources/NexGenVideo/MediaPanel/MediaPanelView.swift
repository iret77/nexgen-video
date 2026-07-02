import SwiftUI

/// Left-sidebar panel hosting the Assets library, Captions, and Music tabs. Its second-level
/// navigation uses the canonical horizontal `SegmentedTabBar` — the same idiom as the Project cockpit —
/// so the sidebar speaks one consistent sub-navigation language (docs/UI_UX_CONCEPT.md §2.1).
struct MediaPanelView: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var panelTab: PanelTab = .media

    enum PanelTab: String, CaseIterable {
        case media = "Assets", captions = "Captions", music = "Music"
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabBar(
                titles: PanelTab.allCases.map(\.rawValue),
                selected: panelTab.rawValue,
                raisedBackground: true
            ) { title in
                if let tab = PanelTab.allCases.first(where: { $0.rawValue == title }) {
                    withAnimation(.easeInOut(duration: AppTheme.Anim.transition)) { panelTab = tab }
                }
            }
            Group {
                switch panelTab {
                case .media: MediaTab()
                case .captions: CaptionTab()
                case .music: MusicTab()
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .onChange(of: editor.mediaPanelShowMediaTabTick) { _, _ in
            withAnimation(.easeInOut(duration: AppTheme.Anim.transition)) { panelTab = .media }
        }
    }
}
