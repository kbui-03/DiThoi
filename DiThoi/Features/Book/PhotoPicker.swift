import SwiftUI
import PhotosUI

/// The system photo picker, out of process.
///
/// `PHPickerViewController` is used rather than `PhotosPicker` because it needs
/// no photo-library permission at all — the user picks in Apple's UI and the
/// app only ever receives what they chose. For an app whose Papers screen
/// promises nothing leaves the phone, not holding library access is the point.
///
/// One picker, two jobs. The journal and a moment want a single photograph;
/// a passport wants the several pages of it in one pass, which is what
/// `selectionLimit` is for. A second copy of this for the second job is how the
/// two would drift.
struct PhotoPicker: UIViewControllerRepresentable {
    /// `0` would be "unlimited"; the callers that want one pass nothing.
    var selectionLimit: Int = 1
    var onPicked: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: ([UIImage]) -> Void
        init(onPicked: @escaping ([UIImage]) -> Void) { self.onPicked = onPicked }

        /// Loaded concurrently, delivered in the order they were picked.
        ///
        /// `loadObject` completions arrive whenever each one happens to finish,
        /// so appending to an array as they land shuffles the pages — and a
        /// passport whose photo page comes back after the visa stamps is the
        /// same class of bug as a waypoint lookup answering `.first`: nothing
        /// crashes, nothing is missing, and the thing is silently wrong. Each
        /// result is written to its own slot and the batch is handed over once
        /// every slot has reported.
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                // Cancelled. Say so, rather than leaving the caller's
                // `isPresented` set with nothing on the way — the picker's own
                // view controller dismisses itself either way, so a silent
                // return here strands whatever presented it.
                Task { @MainActor [onPicked] in onPicked([]) }
                return
            }

            let box = Slots(count: results.count, onPicked: onPicked)
            for (position, result) in results.enumerated() {
                let provider = result.itemProvider
                guard provider.canLoadObject(ofClass: UIImage.self) else {
                    Task { @MainActor in box.report(nil, at: position) }
                    continue
                }
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    let image = object as? UIImage
                    Task { @MainActor in box.report(image, at: position) }
                }
            }
        }

        /// Ordered gather. `@MainActor` so the counter needs no lock of its own.
        @MainActor
        private final class Slots {
            private var images: [UIImage?]
            private var reported = 0
            private let onPicked: ([UIImage]) -> Void

            init(count: Int, onPicked: @escaping ([UIImage]) -> Void) {
                images = Array(repeating: nil, count: count)
                self.onPicked = onPicked
            }

            func report(_ image: UIImage?, at position: Int) {
                guard position < images.count else { return }
                images[position] = image
                reported += 1
                guard reported == images.count else { return }
                // Anything that failed to load is dropped rather than held as a
                // gap. The batch result is what tells the reader a page is
                // missing; a nil in the middle would just move that silence.
                onPicked(images.compactMap { $0 })
            }
        }
    }
}

/// The camera, for a photograph that doesn't exist yet.
///
/// `UIImagePickerController` in `.camera` mode — the one thing `PHPicker`
/// cannot do. It asks for camera access, not library access; what it takes is
/// handed back once and the controller is let go.
struct CameraCapture: UIViewControllerRepresentable {
    /// Nil when cancelled — said out loud, for the reason the picker's
    /// cancel is: a silent return strands whatever presented it.
    var onCaptured: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCaptured: (UIImage?) -> Void
        init(onCaptured: @escaping (UIImage?) -> Void) { self.onCaptured = onCaptured }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCaptured(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCaptured(nil)
        }
    }
}

/// Where the photograph comes from, asked each time.
enum PhotoSource: String, Identifiable {
    case camera, library
    var id: String { rawValue }
}

/// Camera or library, then the crop, in that order and without racing.
///
/// Two presentations, and neither end of the picker is reliably last. It
/// dismisses *itself* the moment somebody taps a photograph — synchronously,
/// inside `didFinishPicking` — and only hands the image over once `loadObject`
/// has finished, which is a runloop turn or more later. So driving the crop off
/// `onDismiss` opens it with nothing to crop (it did, and the screen silently
/// went back to the composer with no photograph attached), and driving it off
/// `onPicked` can start a presentation while the sheet is still animating out.
///
/// Whichever of the two happens last opens the crop, and `open()` is the one
/// place that decides. Cancelling delivers an empty batch, so `pending` stays
/// nil and nothing opens. The camera ends the same way, so it goes through the
/// same door and the same crop — one square, one dpi warning, whichever source.
///
/// **`isPresented` is read and handed back at once.** The caller sets it; this
/// clears it and drives its own state from there. Left set while the source
/// dialog was dismissed by a tap outside, it would stay `true`, and the next
/// tap on the photo box would set `true` over `true` and open nothing.
///
/// One modifier rather than a copy in each composer, because the two would
/// drift and only one of them would get this comment.
private struct PhotoIntake: ViewModifier {
    @Binding var isPresented: Bool
    /// Whether a photograph *taken here* also reached the camera roll. Only
    /// asked of the camera: a picked photo is already in the library.
    let onSavedToLibrary: ((Bool) -> Void)?
    let onCropped: (UIImage) -> Void

    /// The photograph, once the picker or the camera has handed it over.
    @State private var pending: UIImage?
    /// The crop's presentation *is* its subject. A separate `Bool` and payload
    /// can disagree, and did: the cover opened with `pending` still nil and
    /// drew an empty white screen over the composer, with the main thread idle
    /// and nothing in the log. An `item:` cover cannot reach that state.
    @State private var cropping: PickedPhoto?
    @State private var choosing = false
    @State private var source: PhotoSource?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, asked in
                guard asked else { return }
                isPresented = false
                // No dialog with one answer in it. The simulator has no
                // camera, and nor does a phone with it restricted.
                if CameraCapture.isAvailable { choosing = true } else { source = .library }
            }
            .confirmationDialog("A photograph", isPresented: $choosing, titleVisibility: .hidden) {
                Button("Take a photo") { source = .camera }
                Button("Choose one") { source = .library }
                Button("Not now", role: .cancel) {}
            }
            .sheet(item: $source, onDismiss: open) { chosen in
                switch chosen {
                case .library:
                    PhotoPicker { images in
                        // One page, one photograph — the picker is limited to
                        // one, so this is the whole batch and not a truncation.
                        pending = images.first
                        open()
                    }
                    .ignoresSafeArea()
                case .camera:
                    CameraCapture { image in
                        pending = image
                        if let image { saveToLibrary(image) }
                        source = nil
                    }
                    .ignoresSafeArea()
                }
            }
            .fullScreenCover(item: $cropping, onDismiss: { pending = nil }) { photo in
                PhotoCropView(source: photo.image, onUse: onCropped)
            }
    }

    private func open() {
        guard source == nil, let pending else { return }
        cropping = PickedPhoto(image: pending)
    }

    /// The whole frame, uncropped — the square is the book's, the photograph
    /// is theirs. Through `PhotoLibrary`, add-only, so the picker's promise
    /// stands. Refused, the app's own copy is kept regardless and the caller
    /// is told.
    private func saveToLibrary(_ image: UIImage) {
        let report = onSavedToLibrary
        PhotoLibrary.add(image) { saved in report?(saved) }
    }
}

private struct PickedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

extension View {
    /// Take or pick a photograph and choose the square the book gets.
    /// `onCropped` runs only on "use this square", so backing out of any step
    /// leaves whatever is already attached alone.
    func photoIntake(isPresented: Binding<Bool>,
                     onSavedToLibrary: ((Bool) -> Void)? = nil,
                     onCropped: @escaping (UIImage) -> Void) -> some View {
        modifier(PhotoIntake(isPresented: isPresented, onSavedToLibrary: onSavedToLibrary,
                             onCropped: onCropped))
    }
}

/// A stored photo, or the hatched stand-in when there isn't one yet.
///
/// **Square, always.** The printed page is square — `BookSpec` is 8 × 8 inches
/// — and photographs now arrive already cropped to a square somebody chose in
/// `PhotoCropView`. This used to ask for a height and fill the width, which
/// made a third aperture: the composer cropped one way, `BookSpreadView`
/// cropped another, and a landscape photograph was cramped on screen into
/// neither of the shapes it would print in.
///
/// A photograph saved before the crop existed is not square, and drawn here it
/// is centre-cropped — which is exactly what the book already does to it. That
/// is the point: the app stops disagreeing with the print file without a
/// migration or a re-encode.
struct JournalPhoto: View {
    let photoID: String?
    /// A fixed side, or nil for "as wide as you are given, and as tall".
    ///
    /// Not a height. `TrailView` used to wrap this in a second square frame
    /// with a comment explaining that asking for a height alone gave every
    /// moment *without* a photograph a taller box than the ones with — the
    /// shape was the caller's problem when it should never have been anyone's.
    var side: CGFloat?
    var caption: String?
    /// Thumbnails are half the size and used in lists.
    var usesThumbnail: Bool = false

    var body: some View {
        square.photoMount()
    }

    @ViewBuilder private var square: some View {
        if let side {
            face.frame(width: side, height: side).clipped()
        } else {
            // The square is taken from the width it is given rather than from
            // the content, the same trick the stamp badges use — a badge that
            // sized itself from its own text shrank its circle and truncated
            // the code inside it.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { face }
                .clipped()
        }
    }

    @ViewBuilder private var face: some View {
        if let photoID, let image = loaded(photoID) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Hatching().overlay { HatchCaption(caption) }
        }
    }

    private func loaded(_ id: String) -> UIImage? {
        usesThumbnail ? PhotoStore.shared.thumbnail(id) : PhotoStore.shared.image(id)
    }
}
