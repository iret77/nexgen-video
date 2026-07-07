import Foundation
import Testing
import NexGenEngine
import MusicvideoPlugin

@testable import NexGenVideo

@Suite("Installed native pack")
struct InstalledPackTests {

    @Test func musicvideoPackIsListed() {
        // Packs are loaded at runtime now (empty compiled-in list); register the
        // loadable pack the way the host's PluginLoader does before asserting.
        PackCatalog.register(MusicvideoPack())
        let pack = InstalledPack.named("musicvideo")
        #expect(pack != nil)
        // Mirrors the retired plugins/musicvideo/ngv-plugin.json values.
        #expect(pack?.displayName == "Music Video Studio")
        #expect(pack?.tagline?.isEmpty == false)
        #expect(InstalledPack.all.contains { $0.name == "musicvideo" })
    }

    @Test func unknownPackResolvesToNil() {
        #expect(InstalledPack.named("does-not-exist") == nil)
        #expect(InstalledPack.named(nil) == nil)
    }
}
