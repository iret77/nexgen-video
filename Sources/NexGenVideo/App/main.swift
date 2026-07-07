import AppKit

Log.bootstrap()
Telemetry.start()
BundledFonts.register()
ModelCatalog.shared.configure()
ModelCatalog.shared.load(entries: FalModelRegistry.entries + MarbleModelRegistry.entries + RunwayModelRegistry.entries + HiggsfieldModelRegistry.entries)

// Load installed format packs before any UI reads the catalog. Packs ship as
// signed `.ngvpack` bundles outside the DMG; incompatible/unsigned ones surface
// in the picker with a reason instead of loading (never a crash).
PluginLoader.loadInstalled()

// Shorten the default tooltip delay from 2s to 0.01s.
UserDefaults.standard.set(10, forKey: "NSInitialToolTipDelay")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = MainMenuBuilder.buildMenu()
app.run()
