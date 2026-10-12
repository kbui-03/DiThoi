import SwiftUI
import Photos

/// The one way anything is put in the traveller's Photos.
///
/// Add-only access: the app can put a picture in the library and still cannot
/// read one out, so the picker's promise — the app only ever receives what
/// somebody chose — stands. Two things write here, the camera's full frame and
/// the week's postcard, and they used to be about to be two copies of the same
/// permission dance.
///
/// The completion says what actually happened. `performChanges` reporting
/// success is the only thing that counts as saved; a refusal is `false`, never
/// silence, because "no error" is not "it worked".
enum PhotoLibrary {
    /// A photograph, as the camera took it.
    static func add(_ image: UIImage, completion: @escaping @MainActor (Bool) -> Void) {
        perform({ PHAssetCreationRequest.creationRequestForAsset(from: image) }, completion: completion)
    }

    /// A PNG, kept as a PNG: going through `UIImage` would re-encode it.
    static func add(png: Data, completion: @escaping @MainActor (Bool) -> Void) {
        perform({
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = "public.png"
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: options)
        }, completion: completion)
    }

    private static func perform(_ change: @escaping () -> Void,
                                completion: @escaping @MainActor (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges(change) { saved, _ in
                Task { @MainActor in completion(saved) }
            }
        }
    }
}
