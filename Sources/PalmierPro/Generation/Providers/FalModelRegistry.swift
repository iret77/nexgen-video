import Foundation

/// Built-in fal.ai image models. Each `id` is also the fal queue endpoint path.
enum FalModelRegistry {
    static let entries: [CatalogEntry] = [
        imageEntry(
            id: "fal-ai/flux/schnell",
            displayName: "FLUX.1 [schnell] (fast)"
        ),
        imageEntry(
            id: "fal-ai/flux/dev",
            displayName: "FLUX.1 [dev]"
        ),
    ]

    private static let aspectRatios = ["1:1", "16:9", "9:16", "4:3", "3:4"]

    private static func imageEntry(id: String, displayName: String) -> CatalogEntry {
        let caps = ImageCaps(
            resolutions: nil,
            aspectRatios: aspectRatios,
            qualities: nil,
            supportsImageReference: false,
            maxImages: 4
        )
        return CatalogEntry(
            id: id,
            kind: .image,
            displayName: displayName,
            allowedEndpoints: [id],
            responseShape: .images,
            uiCapabilities: .image(caps),
            creditsPerImage: nil
        )
    }
}
