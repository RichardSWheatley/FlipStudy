import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

/// Create a deck by scanning a page (device camera) or picking a photo, running
/// on-device OCR, then turning the recognized text into draft cards. When the
/// device can run Apple's on-device model, an AI extractor reads the page into
/// real question/answer pairs; otherwise it falls back to a deterministic
/// "Term: definition" line splitter so scanning still works everywhere. Either
/// way the cards are a preview the user reviews and edits before the deck is
/// created.
struct PhotoDeckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var extractedText = ""
    @State private var isRecognizing = false
    @State private var isGenerating = false
    @State private var showScanner = false
    @State private var errorMessage: String?
    @State private var draftCards: [(front: String, back: String)] = []

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedText: String {
        extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedText.isEmpty && !isRecognizing && !isGenerating
    }

    private var canCreate: Bool {
        !trimmedTitle.isEmpty && !draftCards.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deck") {
                    TextField("Title (e.g. Biology Chapter 3)", text: $title)
                }

                Section {
                    if DocumentScanner.isSupported {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan a Page", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose a Photo", systemImage: "photo.on.rectangle")
                    }
                } header: {
                    Text("Capture")
                } footer: {
                    Text(captureFootnote)
                }

                if isRecognizing {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading text…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if !trimmedText.isEmpty || isRecognizing {
                    Section {
                        TextEditor(text: $extractedText)
                            .frame(minHeight: 140)
                            .font(.body)
                        Button {
                            generateCards()
                        } label: {
                            if isGenerating {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Making cards…")
                                }
                            } else {
                                Label(draftCards.isEmpty ? "Make Cards" : "Redo Cards",
                                      systemImage: "rectangle.stack.badge.plus")
                            }
                        }
                        .disabled(!canGenerate)
                    } header: {
                        Text("Recognized Text")
                    } footer: {
                        Text(recognizedFootnote)
                    }
                }

                if !draftCards.isEmpty {
                    Section {
                        ForEach(Array(draftCards.enumerated()), id: \.offset) { _, card in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.front)
                                    .font(.body.weight(.medium))
                                if !card.back.isEmpty {
                                    Text(card.back)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Preview (\(draftCards.count))")
                    } footer: {
                        Text("Review each card before creating the deck.")
                    }
                }
            }
            .navigationTitle("Scan a Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { images in
                    showScanner = false
                    recognize(images: images)
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPickedImage(newItem) }
            }
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't load that photo."
                return
            }
            recognize(images: [image])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var captureFootnote: String {
        "Text is read on your device — nothing leaves your phone. Each line becomes a card you can review and edit."
    }

    private func recognize(images: [UIImage]) {
        guard !images.isEmpty else { return }
        errorMessage = nil
        isRecognizing = true
        Task {
            var lines: [String] = []
            do {
                for image in images {
                    lines += try await TextRecognizer.recognize(image: image)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            append(lines: lines)
            isRecognizing = false
            if !trimmedText.isEmpty {
                generateCards()
            }
        }
    }

    private func append(lines: [String]) {
        guard !lines.isEmpty else { return }
        let joined = lines.joined(separator: "\n")
        if extractedText.isEmpty {
            extractedText = joined
        } else {
            extractedText += "\n" + joined
        }
    }

    // MARK: - Card extraction

    /// Turn the recognized text into draft cards. When the on-device model is
    /// available, the AI extractor reads the whole page and writes real
    /// question/answer pairs. When it isn't (older hardware, Apple Intelligence
    /// off, or the model returns nothing), fall back to the deterministic line
    /// splitter so scanning still produces cards.
    private func generateCards() {
        let text = trimmedText
        guard !text.isEmpty, !isGenerating else { return }
        errorMessage = nil
        isGenerating = true
        Task {
            var cards: [(front: String, back: String)]
            do {
                cards = try await AICardGenerator.makeCards(fromText: text)
            } catch {
                cards = CardGenerator.cards(from: text)
            }
            // If the AI came back empty, still give the splitter a chance.
            if cards.isEmpty {
                cards = CardGenerator.cards(from: text)
            }
            draftCards = cards
            errorMessage = cards.isEmpty ? "Couldn't find any cards in that text." : nil
            isGenerating = false
        }
    }

    /// Footer under the recognized text, describing which extractor will run so
    /// the user knows what to expect (AI page reading vs. the line splitter).
    private var recognizedFootnote: String {
        if AICardGenerator.isAvailable {
            return "The AI reads this text on your device and writes question-and-answer cards. Edit the text above and redo if the cards need tweaking."
        }
        return "Cards are split line-by-line. Use \"Term: definition\" or \"Term — definition\" to split front and back. Edit the text above and redo if needed."
    }

    private func create() {
        let deck = Deck(title: trimmedTitle,
                        subject: "",
                        source: .photo)
        context.insert(deck)
        for draft in draftCards {
            let card = Card(front: draft.front, back: draft.back)
            card.deck = deck
            context.insert(card)
        }
        dismiss()
    }
}

extension DocumentScanner {
    /// Whether document scanning is available (camera-equipped hardware only).
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }
}
