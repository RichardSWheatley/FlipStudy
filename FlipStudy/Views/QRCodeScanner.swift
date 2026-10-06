import SwiftUI
import VisionKit

/// Scans a family code's QR with the camera, so a code can be handed over as a
/// printed or texted image instead of a string of characters read aloud.
///
/// Camera-only: `DataScannerViewController` needs real hardware, so the sheet
/// around this falls back to typing the code when it isn't available.
struct QRCodeScanner: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    /// Whether live scanning can run — false in the simulator and on hardware
    /// without the Neural Engine support the scanner needs.
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        // Scanning can only start once the controller is in the view hierarchy,
        // which is why this isn't in `makeUIViewController`.
        guard !controller.isScanning else { return }
        try? controller.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let parent: QRCodeScanner
        /// The camera keeps recognizing the same code many times a second; the
        /// first hit is the only one that should redeem anything.
        private var hasReported = false

        init(_ parent: QRCodeScanner) {
            self.parent = parent
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !hasReported else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue,
                   !payload.isEmpty {
                    hasReported = true
                    scanner.stopScanning()
                    parent.onFound(payload)
                    return
                }
            }
        }
    }
}
