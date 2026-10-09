import SwiftUI
import SwiftData
import CloudKit

/// App settings. The one gated control is Cloud AI: because FlipStudy is aimed
/// at kids, turning it on requires a grown-up to pass a simple math check first.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProStore.self) private var proStore
    @Environment(FamilyLinkRouter.self) private var linkRouter
    @Query private var settingsList: [AppSettings]

    @State private var showingPaywall = false
    @State private var isRestoring = false
    /// The code screen, when it's showing, and any code to pre-fill from a
    /// tapped join link. One value for the same reason as `parentGate`: a flag
    /// plus a separate pre-fill opened the screen with the previous (empty) code.
    @State private var familyCodeRequest: FamilyCodeRequest?
    /// The pending grown-up check: what it is for, and what to do once it
    /// passes. Carried as one value rather than a flag plus separate state
    /// because `.sheet(isPresented:)` builds its body from what SwiftUI already
    /// has — setting a purpose and raising the flag in the same action could
    /// still present the *previous* purpose, which asked permission for the
    /// wrong thing. `.sheet(item:)` is always built from the item.
    @State private var parentGate: ParentGateRequest?
    /// iOS has notifications switched off for FlipStudy, so the reminder can't work.
    @State private var notificationsBlocked = false
    @State private var iCloudStatus: ICloudStatus = .checking
    @State private var apiKey = ""
    /// When true the API key is shown as plain text so a grown-up can verify the
    /// exact characters. A masked SecureField hides paste corruption (truncation,
    /// autofill hijacking), which looks identical to a wrong key — so we let the
    /// key be revealed and checked.
    @State private var revealKey = false
    @State private var region = ""
    @State private var isTesting = false
    /// Result of the last "Test connection" tap: success text or a parsed error.
    @State private var testResult: TestResult?

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    private var settings: AppSettings? { settingsList.first }

    /// Reflects the "stay on this phone" preference for cloud-unlocked users.
    private var onDeviceBinding: Binding<Bool> {
        Binding(
            get: { settings?.prefersOnDeviceCards ?? false },
            set: { settings?.prefersOnDeviceCards = $0 }
        )
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { settings?.reminderEnabled ?? false },
            set: { on in
                guard on else {
                    settings?.reminderEnabled = false
                    StudyProgress.refresh(context: context, settings: settings)
                    return
                }
                Task {
                    if await StudyNotifier.requestPermission() {
                        settings?.reminderEnabled = true
                        notificationsBlocked = false
                    } else {
                        notificationsBlocked = true
                    }
                    StudyProgress.refresh(context: context, settings: settings)
                }
            }
        )
    }

    /// The reminder time, stored as minutes after midnight.
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = settings?.reminderMinutes ?? AppSettings.defaultReminderMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings?.reminderMinutes = (parts.hour ?? 17) * 60 + (parts.minute ?? 0)
                StudyProgress.refresh(context: context, settings: settings)
            }
        )
    }

    private var goalBinding: Binding<Int> {
        Binding(
            get: { settings?.dailyGoal ?? AppSettings.defaultDailyGoal },
            set: {
                settings?.dailyGoal = $0
                StudyProgress.refresh(context: context, settings: settings)
            }
        )
    }

    private var proFootnote: String {
        guard proStore.isPro || CardEngine.cloudUnlocked(settings) else {
            return "A one-time purchase unlocks the on-device Apple Intelligence features: AI decks from a typed subject, and smart question-and-answer scanning."
        }
        switch CardEngine.active(for: settings) {
        case .cloud:
            return "Smart decks and page scanning are turned on, and FlipStudy Cloud is making the cards."
        case .onDevice:
            return "Thanks! On-device AI decks and smart page scanning are turned on."
        }
    }

    /// The lead sentence has to stop claiming cards are drafted on the phone
    /// once FlipStudy Cloud is the one drafting them.
    private var translationFootnote: String {
        let lead = CardEngine.active(for: settings) == .cloud
            ? "Cards are drafted by FlipStudy Cloud."
            : "Cards are always drafted on your device — free and private."
        return lead + " This only changes the engine used to translate language decks: leave it off for Apple's on-device translator, or turn it on to use Google or Microsoft with your own API key. A grown-up has to turn this on."
    }

    private var cloudCardsFootnote: String {
        guard CardEngine.cloudUnlocked(settings) else {
            return "FlipStudy Cloud makes cards with a much larger AI than this phone can hold, and works even on iPhones without Apple Intelligence. It needs a family code. A grown-up has to enter it."
        }
        return settings?.prefersOnDeviceCards == true
            ? "Cards are being made on this phone, so no text is sent anywhere. Turn this off to use FlipStudy Cloud again."
            : "Cards are made by FlipStudy Cloud. The text you scan or type, and any card you ask it to explain, is sent over an encrypted connection and isn't stored there."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThemePicker()
                } header: {
                    Text("🎨 Pick Your Icon")
                } footer: {
                    Text("Choose a grade and a color. They change FlipStudy's colors, its widget, and its icon on your Home Screen.")
                }

                Section {
                    if proStore.isPro {
                        Label {
                            Text("Pro unlocked")
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            Label("Unlock FlipStudy Pro", systemImage: "sparkles")
                        }
                        Button {
                            Task { await restorePurchase() }
                        } label: {
                            if isRestoring {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Restoring…")
                                }
                            } else {
                                Text("Restore Purchase")
                            }
                        }
                        .disabled(isRestoring)
                    }
                } header: {
                    Text("FlipStudy Pro")
                } footer: {
                    Text(proFootnote)
                }

                Section {
                    Toggle("Daily reminder", isOn: reminderBinding)
                    if settings?.reminderEnabled == true {
                        DatePicker("Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                    }
                    Stepper("Daily goal: \(goalBinding.wrappedValue) cards", value: goalBinding, in: 5...200, step: 5)
                } header: {
                    Text("Study Reminders")
                } footer: {
                    Text(notificationsBlocked
                         ? "Notifications are off for FlipStudy. Turn them on in the Settings app, then try again."
                         : "A notification at this time tells you how many cards are ready — only on days something is due.")
                }

                Section {
                    Label(iCloudStatus.title, systemImage: iCloudStatus.systemImage)
                } header: {
                    Text("iCloud")
                } footer: {
                    Text(iCloudStatus.footnote)
                }
                .task { iCloudStatus = await ICloudStatus.current() }

                Section {
                    if CardEngine.cloudUnlocked(settings) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FlipStudy Cloud is on")
                                if let label = settings?.cloudCardsLabel, !label.isEmpty {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                        Toggle("Make cards on this phone instead", isOn: onDeviceBinding)
                        Button(role: .destructive) {
                            // Only this phone loses access; the code itself
                            // stays valid for everyone else it was given to.
                            FamilyAccess.signOut()
                            settings?.cloudCardsEnabled = false
                            settings?.cloudCardsLabel = ""
                            settings?.prefersOnDeviceCards = false
                        } label: {
                            Text("Remove Code")
                        }
                    } else {
                        Button {
                            parentGate = ParentGateRequest(purpose: "turn on FlipStudy Cloud") {
                                familyCodeRequest = FamilyCodeRequest(prefill: "")
                            }
                        } label: {
                            Label("Enter Family Code", systemImage: "qrcode.viewfinder")
                        }
                    }
                } header: {
                    Text("FlipStudy Cloud")
                } footer: {
                    Text(cloudCardsFootnote)
                }

                Section {
                    Toggle("Use a Cloud Translator", isOn: cloudBinding)
                } header: {
                    Text("Translation")
                } footer: {
                    Text(translationFootnote)
                }

                Section {
                    Picker("Engine", selection: providerBinding) {
                        ForEach(TranslationProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    if selectedProvider.isCloud {
                        HStack {
                            // A plain TextField when revealed avoids the strong-
                            // password / autofill overlay that can silently mangle
                            // a pasted key in a SecureField.
                            Group {
                                if revealKey {
                                    TextField("API key", text: $apiKey)
                                } else {
                                    SecureField("API key", text: $apiKey)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.none)
                            .font(.body.monospaced())
                            .onChange(of: apiKey) { _, newValue in
                                CloudTranslationKey.save(newValue, for: selectedProvider)
                            }
                            Button {
                                revealKey.toggle()
                            } label: {
                                Image(systemName: revealKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(revealKey ? "Hide API key" : "Show API key")
                        }
                        if revealKey, !apiKey.isEmpty {
                            Text("^[\(apiKey.count) character](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if selectedProvider == .microsoft {
                            TextField("Region (e.g. eastus)", text: $region)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: region) { _, newValue in
                                    settings?.cloudTranslationRegion =
                                        newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                        }
                        Button {
                            Task { await testConnection() }
                        } label: {
                            if isTesting {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Testing…")
                                }
                            } else {
                                Label("Test Connection", systemImage: "checkmark.seal")
                            }
                        }
                        .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let testResult {
                            switch testResult {
                            case .success(let text):
                                Label(text, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failure(let text):
                                Label(text, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("Translation Engine")
                } footer: {
                    Text(microsoftFootnote)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $parentGate) { request in
                ParentGateView(purpose: request.purpose, onSuccess: request.unlock)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environment(proStore)
            }
            .sheet(item: $familyCodeRequest) { request in
                FamilyCodeView(initialCode: request.prefill) { label in
                    settings?.cloudCardsEnabled = true
                    settings?.cloudCardsLabel = label
                }
            }
            .task(id: linkRouter.pendingCode) {
                guard let code = linkRouter.pendingCode else { return }
                // Already on: Settings itself says so, nothing to redeem.
                guard !CardEngine.cloudUnlocked(settings) else {
                    linkRouter.pendingCode = nil
                    return
                }
                // Let this sheet finish presenting before stacking the
                // grown-up check on top of it.
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                parentGate = ParentGateRequest(purpose: "turn on FlipStudy Cloud") {
                    familyCodeRequest = FamilyCodeRequest(prefill: code)
                }
                linkRouter.pendingCode = nil
            }
            .onAppear {
                ensureSettings()
                // Move a pre-1.2 single shared key onto the engine that's set,
                // then load that engine's own key.
                CloudTranslationKey.migrateLegacyKey(to: selectedProvider)
                apiKey = CloudTranslationKey.read(for: selectedProvider)
                region = settings?.cloudTranslationRegion ?? ""
            }
            .onChange(of: selectedProvider) { _, newProvider in
                // Each engine has its own key slot — swap the field to the newly
                // selected engine's key so a Microsoft key can never be shown or
                // sent under Google (or vice versa).
                apiKey = CloudTranslationKey.read(for: newProvider)
                revealKey = false
                testResult = nil
            }
        }
    }

    private func restorePurchase() async {
        isRestoring = true
        await proStore.restore()
        isRestoring = false
    }

    private var selectedProvider: TranslationProvider {
        settings?.translationProvider ?? .apple
    }

    /// The engine footnote, with an extra line for Microsoft explaining that a
    /// region is required — the missing region is the usual cause of a 401.
    private var microsoftFootnote: String {
        if selectedProvider == .microsoft {
            return selectedProvider.footnote
                + " Microsoft also needs the Region from your Translator resource's \"Keys and Endpoint\" page (e.g. eastus), or it returns a 401."
        }
        return selectedProvider.footnote
    }

    /// Fire a tiny English → Italian translation with the entered key/region and
    /// report the parsed result, so key setup can be verified without leaving
    /// Settings. Uses the same `CloudTranslator` the app uses, so a success here
    /// means Generate Cards will work too.
    private func testConnection() async {
        isTesting = true
        testResult = nil
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let results = try await CloudTranslator(provider: selectedProvider, apiKey: key,
                                                    source: .english, target: .italian,
                                                    region: trimmedRegion)
                .translate(["Hello"])
            let translated = results.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if translated.isEmpty {
                testResult = .failure("Connected, but no translation came back. Check the key's resource type.")
            } else {
                testResult = .success("Works! \"Hello\" → \"\(translated)\"")
            }
        } catch {
            testResult = .failure(error.localizedDescription)
        }
        isTesting = false
    }

    /// Selecting a cloud engine requires Cloud AI to be on. If it isn't, picking
    /// a cloud engine opens the grown-up gate, which both enables Cloud AI and
    /// sets the engine once passed.
    private var providerBinding: Binding<TranslationProvider> {
        Binding(
            get: { selectedProvider },
            set: { newValue in
                guard let settings else { return }
                if newValue.isCloud && !settings.cloudAIEnabled {
                    parentGate = ParentGateRequest(purpose: "turn on a cloud translator") {
                        settings.cloudAIEnabled = true
                        settings.translationProvider = newValue
                    }
                } else {
                    settings.translationProvider = newValue
                }
            }
        )
    }

    /// Reflects the stored flag, but flipping it ON only opens the parent gate —
    /// the flag itself is set once the grown-up passes the check.
    private var cloudBinding: Binding<Bool> {
        Binding(
            get: { settings?.cloudAIEnabled ?? false },
            set: { newValue in
                if newValue {
                    parentGate = ParentGateRequest(purpose: "turn on a cloud translator") {
                        settings?.cloudAIEnabled = true
                    }
                } else {
                    settings?.cloudAIEnabled = false
                    // Fall back to the free on-device engine when cloud is off.
                    settings?.translationProvider = .apple
                }
            }
        )
    }

    private func ensureSettings() {
        if settingsList.isEmpty {
            context.insert(AppSettings())
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// A lightweight "ask a grown-up" gate: solve a multiplication problem that's
/// beyond a young child. Not real security — just a speed bump before enabling
/// an online feature, matching common kids-app practice.
/// The code screen being shown, with any code a join link brought along.
private struct FamilyCodeRequest: Identifiable {
    let id = UUID()
    let prefill: String
}

/// A pending grown-up check — what it's guarding, and what to do once it's
/// passed.
private struct ParentGateRequest: Identifiable {
    let id = UUID()
    let purpose: String
    let unlock: () -> Void
}

private struct ParentGateView: View {
    @Environment(\.dismiss) private var dismiss
    /// What the grown-up is being asked to allow — the gate guards both the
    /// cloud translator and FlipStudy Cloud, and naming the wrong one reads as
    /// the app asking permission for something it isn't about to do.
    var purpose: String = "turn on a cloud translator"
    let onSuccess: () -> Void

    @State private var first = Int.random(in: 6...9)
    @State private var second = Int.random(in: 6...9)
    @State private var answer = ""
    @State private var showedWrong = false

    private var canConfirm: Bool {
        !answer.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("\(first) × \(second) =")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        TextField("Answer", text: $answer)
                            .keyboardType(.numberPad)
                    }
                    if showedWrong {
                        Text("That's not right. Try again.")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Grown-Up Check")
                } footer: {
                    Text("Ask a grown-up to solve this to \(purpose).")
                }
            }
            .navigationTitle("Grown-Up Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { check() }
                        .disabled(!canConfirm)
                }
            }
        }
    }

    private func check() {
        if Int(answer.trimmingCharacters(in: .whitespaces)) == first * second {
            onSuccess()
            dismiss()
        } else {
            showedWrong = true
            answer = ""
            first = Int.random(in: 6...9)
            second = Int.random(in: 6...9)
        }
    }
}

/// Whether decks are reaching iCloud, in words a family can act on.
private enum ICloudStatus {
    case checking, syncing, signedOut, restricted, unavailable, deviceOnly

    static func current() async -> ICloudStatus {
        // Only ask CloudKit when the store actually opened with sync; a build
        // without the iCloud entitlement can't create the container at all.
        guard Persistence.isSyncing else { return .deviceOnly }
        switch try? await CKContainer(identifier: Persistence.cloudContainerID).accountStatus() {
        case .available: return .syncing
        case .noAccount: return .signedOut
        case .restricted: return .restricted
        default: return .unavailable
        }
    }

    var title: String {
        switch self {
        case .checking: "Checking iCloud…"
        case .syncing: "Syncing with iCloud"
        case .signedOut: "Not signed in to iCloud"
        case .restricted: "iCloud is restricted on this device"
        case .unavailable: "iCloud isn't available right now"
        case .deviceOnly: "Saved on this device only"
        }
    }

    var systemImage: String {
        switch self {
        case .syncing: "checkmark.icloud"
        case .checking: "icloud"
        default: "icloud.slash"
        }
    }

    var footnote: String {
        switch self {
        case .signedOut:
            "Sign in to iCloud in the Settings app to keep your decks and streak on every iPhone and iPad you use. Until then, everything stays on this device."
        case .restricted:
            "Screen Time or a device profile is blocking iCloud, so decks stay on this device."
        case .deviceOnly:
            "This copy of FlipStudy can't use iCloud, so decks stay on this device."
        default:
            "Your decks, cards and streak sync through your own iCloud account to every iPhone and iPad signed in to it. Only you can see them. Settings stay on each device."
        }
    }
}
