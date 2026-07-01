import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

/// Create a deck by scanning a page (device camera) or picking a photo, running
/// on-device OCR, then turning the recognized text into draft cards.
struct PhotoDeckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var extractedText = ""
    @State private var isRecognizing = false
    @State private var showScanner = false
    @State private var errorMessage: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftCards: [(front: String, back: String)] {
        CardGenerator.cards(from: extractedText)
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
                    Text("Text is read on your device. Put one term per line — use \"Term: definition\" or \"Term — definition\" to split front and back.")
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

                Section("Recognized Text") {
                    TextEditor(text: $extractedText)
                        .frame(minHeight: 140)
                        .font(.body)
                }

                if !draftCards.isEmpty {
                    Section("Preview (\(draftCards.count))") {
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
