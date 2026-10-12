import SwiftUI
import VisionKit

/// The system document scanner — edge detection, perspective correction, the
/// lot — for passports and visas.
///
/// Camera only, so it doesn't exist in the simulator. `DocumentCapture` below
/// falls back to the photo picker there and on any device that reports no
/// scanner, which also covers importing a visa PDF screenshot someone emailed.
struct DocumentScanner: UIViewControllerRepresentable {
    var onScanned: ([UIImage]) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScanned: onScanned, onCancel: onCancel) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScanned: ([UIImage]) -> Void
        private let onCancel: () -> Void

        init(onScanned: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScanned = onScanned
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            controller.dismiss(animated: true)
            onScanned(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onCancel()
        }
    }
}

/// Where a page comes from.
///
/// This was "scanner if there is a camera, photo picker if there isn't" — a
/// fallback, which is the wrong shape once there are three real sources. A
/// visa arrives as a PDF and a boarding pass is already in the camera roll;
/// neither is a thing you photograph.
///
/// It also fixes a stranded sheet. The picker branch dropped `onCancel`
/// entirely, and `PHPickerViewController` dismisses itself, so cancelling left
/// the caller's `isPresented` set with nothing on screen and no way back — on
/// the only path a simulator can take, which is the path every screenshot of
/// this flow takes. Every route out of here now reports.
struct DocumentCapture: View {
    var onCaptured: ([UIImage]) -> Void
    var onCancel: () -> Void

    @State private var source: Source?
    @State private var importing = false
    @State private var problem: String?

    private enum Source: String, Identifiable {
        case camera, library
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Add a page", trailing: "Cancel") { onCancel() }

            VStack(alignment: .leading, spacing: 0) {
                if DocumentScanner.isAvailable {
                    row("Photograph it", note: "Edges and perspective are straightened for you.") {
                        source = .camera
                    }
                }
                row("From photos", note: "Several at once, in the order you pick them.") {
                    source = .library
                }
                row("From a file", note: "A PDF, up to \(DocumentImport.pageLimit) pages.",
                    showsRule: false) {
                    importing = true
                }

                if let problem {
                    Aside(text: problem, size: 12, color: Palette.a800)
                        .padding(.top, Space.s3)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s2)

            Spacer()
        }
        .background(Palette.bg)
        .fullScreenCover(item: $source) { which in
            switch which {
            case .camera:
                DocumentScanner(onScanned: onCaptured) { source = nil }
                    .ignoresSafeArea()
            case .library:
                // A cancelled pick reports an empty batch rather than nothing,
                // so this closes instead of sitting there.
                PhotoPicker(selectionLimit: 0) { images in
                    source = nil
                    guard !images.isEmpty else { return }
                    onCaptured(images)
                }
                .ignoresSafeArea()
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task {
                guard let pages = await DocumentImport.pages(from: url) else {
                    problem = "That file couldn't be read."
                    return
                }
                if pages.wasTruncated {
                    problem = "The first \(pages.images.count) pages came in."
                }
                onCaptured(pages.images)
            }
        }
    }

    private func row(_ title: String, note: String, showsRule: Bool = true,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DetailRow(title: title, subtitle: note, titleSize: 17, showsRule: showsRule)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One encrypted page, decrypted only while it's on screen.
struct ScanPage: View {
    let pageID: String
    var height: CGFloat?

    /// Nil while the work is still going. Every other state is an answer.
    ///
    /// This was `UIImage?`, so "still decrypting" and "cannot be decrypted" were
    /// the same value — and since the second one never changes, the screen sat
    /// on "decrypting" for good, under a row reading "encrypted on this phone".
    /// A page whose key is gone is not a page that is loading slowly.
    @State private var page: DocumentStore.Page?

    var body: some View {
        Group {
            switch page {
            case .decrypted(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            case .unreadable(let failure):
                HatchPanel(height: height ?? 216, caption: failure.readerText)
            case .missing:
                HatchPanel(height: height ?? 216, caption: "this scan isn't on this phone")
            case nil:
                HatchPanel(height: height ?? 216, caption: "decrypting")
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: pageID) {
            // Off the main actor: AES on a 2400px JPEG is not free.
            page = await Task.detached(priority: .userInitiated) {
                DocumentStore.shared.page(pageID)
            }.value
        }
    }
}
