import Foundation
@preconcurrency import Vision
import UIKit

/// One line Vision recognized, with where it sat on the page. `box` is in
/// Vision's normalized coordinates: origin bottom-left, so a line higher up the
/// page has the larger `minY`.
struct RecognizedLine: Equatable {
    let text: String
    let box: CGRect
}

/// Runs on-device text recognition (OCR) over an image using the Vision framework.
enum TextRecognizer {
    enum RecognizerError: Error {
        case invalidImage
    }

    /// Languages to recognize. Scanned study pages are routinely bilingual — an
    /// English/Italian vocabulary list, say — and Vision only recognizes the
    /// languages it is told about. Left unset it assumes English alone and
    /// "corrects" foreign words into English-looking nonsense (this is what
    /// turned *supermercato* into *supermnercalu*), so every language the app
    /// can put on a card is offered here.
    private static let desiredLanguages = [
        "en-US", "it-IT", "es-ES", "fr-FR", "de-DE", "pt-BR", "ja-JP", "zh-Hans"
    ]

    /// Recognize text in `image` and return it as blocks: wrapped lines joined
    /// back into whole sentences, separate entries left separate.
    static func recognize(image: UIImage) async throws -> [String] {
        TextLayout.blocks(from: try await recognizeLines(image: image))
    }

    /// The raw recognized lines with their page positions, for callers that
    /// need the layout rather than the text.
    static func recognizeLines(image: UIImage) async throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else {
            throw RecognizerError.invalidImage
        }
        let orientation = cgOrientation(from: image.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation -> RecognizedLine? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    return RecognizedLine(text: text, box: observation.boundingBox)
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Ask only for languages this Vision revision actually supports;
            // setting an unsupported one makes the whole request fail.
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let languages = desiredLanguages.filter(supported.contains)
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

/// Rebuilds a page's reading order from the positions Vision reports.
///
/// Vision returns one observation per *visual* line, so a question that wraps
/// across three lines arrives as three fragments. Handing those to the card
/// extractor means asking it to solve a jigsaw before it can do its job — the
/// single biggest cause of poor scanned cards. This joins the fragments back
/// into whole sentences while leaving genuinely separate entries (vocabulary
/// items, list bullets, headings) on their own lines.
enum TextLayout {
    static func blocks(from lines: [RecognizedLine]) -> [String] {
        // Top to bottom. Vision's Y grows upward, so higher on the page is larger.
        let ordered = lines.sorted { $0.box.midY > $1.box.midY }
        guard var current = ordered.first?.text else { return [] }

        // How far right the body text runs, and how tall a typical line is —
        // both are the page's own scale, so this works for a phone screenshot
        // and a textbook photo alike.
        let bodyRight = ordered.map(\.box.maxX).max() ?? 1
        let heights = ordered.map(\.box.height).sorted()
        let lineHeight = heights[heights.count / 2]

        var blocks: [String] = []
        var previous = ordered[0]

        for line in ordered.dropFirst() {
            if continues(previous, into: line, bodyRight: bodyRight, lineHeight: lineHeight) {
                current += " " + line.text
            } else {
                blocks.append(current)
                current = line.text
            }
            previous = line
        }
        blocks.append(current)
        return blocks
    }

    /// True when `line` reads as the continuation of `previous` rather than a
    /// new entry. A wrapped line is recognizable because the line above it ran
    /// out of room — it reaches the right margin — and sits directly above it
    /// with no paragraph break. A list item stops short of the margin, which is
    /// exactly what keeps vocabulary entries from being glued together.
    private static func continues(_ previous: RecognizedLine,
                                  into line: RecognizedLine,
                                  bodyRight: CGFloat,
                                  lineHeight: CGFloat) -> Bool {
        let verticalGap = previous.box.minY - line.box.maxY
        guard verticalGap < lineHeight * 0.75, verticalGap > -lineHeight else { return false }
        // Within ~3 characters of the rightmost text counts as "ran out of room".
        guard previous.box.maxX >= bodyRight - lineHeight * 1.5 else { return false }
        // ...but that alone is measured against the widest line *present*, so on
        // a page of uniformly short lines the longest vocabulary entry would
        // define the margin and the whole list would be glued into one card.
        // A real wrap also means the line physically ran across the page, so
        // require it to span most of the frame.
        guard previous.box.width >= fullLineWidth else { return false }
        return !completesThought(previous.text)
    }

    /// How much of the frame a line must span before running out of room is a
    /// plausible reason for it to end. Below this, a line that stops is a
    /// deliberate break — a list item, a heading, a vocabulary entry.
    private static let fullLineWidth: CGFloat = 0.55

    /// Terminal punctuation means the line ended deliberately, so the next line
    /// starts something new even if the layout looks like a wrap.
    private static func completesThought(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return true }
        return ".!?".contains(last)
    }
}
