import SwiftUI

/// More → Dialer — nostalgic landline keypad (native SwiftUI).
/// Open → US dial tone; digits → DTMF; Call → resolve number → startCall (dial→ringback phases).
struct DialerView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""
    @State private var status = ""
    @State private var showNotFound = false
    @State private var placing = false

    private let keys: [[(label: String, letters: String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("*", ""), ("0", "+"), ("#", "")],
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Text(digits.isEmpty ? " " : formatDisplay(digits))
                .font(.system(size: 36, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("dialer-digits")
                .accessibilityLabel(digits.isEmpty ? "No number entered" : "Number \(digits.map(String.init).joined(separator: " "))")
                .accessibilityAddTraits(.updatesFrequently)

            if !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .accessibilityIdentifier("dialer-status")
            }

            Spacer(minLength: 8)

            VStack(spacing: 14) {
                ForEach(0..<keys.count, id: \.self) { r in
                    HStack(spacing: 22) {
                        ForEach(0..<keys[r].count, id: \.self) { c in
                            let key = keys[r][c]
                            dialKey(key.label, letters: key.letters)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            HStack(spacing: 36) {
                Color.clear.frame(width: 72, height: 72)

                Button {
                    placeCall()
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Brand.goldDeep, in: Circle())
                        .shadow(color: Brand.gold.opacity(0.45), radius: 10, y: 4)
                }
                .accessibilityLabel("Call")
                .accessibilityHint(digits.isEmpty ? "Enter a BlindBandit call number first" : "Place a BlindBandit call to this number")
                .accessibilityIdentifier("dialer-call")
                .disabled(digits.isEmpty || placing)
                .opacity(digits.isEmpty ? 0.45 : 1)

                Button {
                    deleteDigit()
                } label: {
                    Image(systemName: "delete.backward.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 72)
                }
                .accessibilityLabel("Delete")
                .disabled(digits.isEmpty)
                .opacity(digits.isEmpty ? 0.3 : 1)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                    clearAll()
                })
            }
            .padding(.bottom, 28)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Brand.gold.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Dialer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            status = ""
            CallSounds.openDialerIdleTone()
            UIAccessibility.post(notification: .announcement, argument: "Dialer. Dial tone.")
        }
        .onDisappear {
            // If a call was placed, placeCall/startCall owns tones; otherwise stop idle dial.
            if !placing {
                CallSounds.closeDialer()
            }
        }
        .alert("Number not found", isPresented: $showNotFound) {
            Button("OK", role: .cancel) {
                CallSounds.busyOrFailed()
            }
        } message: {
            Text("No BlindBandit profile is assigned to \(formatDisplay(digits)). Set call numbers in Messages & calls settings.")
        }
    }

    private func dialKey(_ label: String, letters: String) -> some View {
        Button {
            press(label)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Text(letters.isEmpty ? " " : letters)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
            .frame(width: 76, height: 76)
            .background(
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            )
            .overlay(
                Circle().strokeBorder(Brand.gold.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voLabel(label, letters: letters))
        .accessibilityIdentifier("dialer-key-\(label)")
        .frame(minWidth: Brand.minTouch, minHeight: Brand.minTouch)
    }

    private func press(_ key: String) {
        digits.append(key)
        status = ""
        CallSounds.dialerKeyPress(key)
        let announce = key == "*" ? "Star" : (key == "#" ? "Pound" : key)
        UIAccessibility.post(notification: .announcement, argument: announce)
        AppHaptics.light()
    }

    private func deleteDigit() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
        AppHaptics.selection()
        if digits.isEmpty {
            CallSounds.openDialerIdleTone()
            status = ""
        }
    }

    private func clearAll() {
        digits = ""
        status = ""
        CallSounds.openDialerIdleTone()
        UIAccessibility.post(notification: .announcement, argument: "Cleared. Dial tone.")
        AppHaptics.warning()
    }

    private func placeCall() {
        let normalized = CallNumberDirectory.normalize(digits)
        guard !normalized.isEmpty else { return }
        if let handle = CallNumberDirectory.resolve(normalized) {
            placing = true
            status = "Calling @\(handle)…"
            // Hand off to outbound machine: connecting dial → ringback.
            CallSounds.closeDialer()
            Task {
                // startCall owns dial → ringback phases.
                await communications.startCall(recipient: handle, video: false)
                placing = false
            }
            UIAccessibility.post(notification: .announcement, argument: "Calling \(handle)")
            AppHaptics.medium()
        } else {
            showNotFound = true
            CallSounds.busyOrFailed()
            status = "Not found"
            UIAccessibility.post(notification: .announcement, argument: "Number not found")
            AppHaptics.error()
        }
    }

    private func formatDisplay(_ raw: String) -> String {
        let d = CallNumberDirectory.normalize(raw)
        // Light NANP grouping when it looks like a US number.
        let digitsOnly = d.filter(\.isNumber)
        if d == digitsOnly {
            if digitsOnly.count == 10 {
                let a = digitsOnly.prefix(3), b = digitsOnly.dropFirst(3).prefix(3), c = digitsOnly.suffix(4)
                return "(\(a)) \(b)-\(c)"
            }
            if digitsOnly.count == 11, digitsOnly.first == "1" {
                let rest = String(digitsOnly.dropFirst())
                let a = rest.prefix(3), b = rest.dropFirst(3).prefix(3), c = rest.suffix(4)
                return "+1 (\(a)) \(b)-\(c)"
            }
        }
        return d
    }

    private func voLabel(_ label: String, letters: String) -> String {
        switch label {
        case "*": return "Star"
        case "#": return "Pound"
        case "0": return letters.isEmpty ? "0" : "0, plus"
        default:
            return letters.isEmpty ? label : "\(label), \(letters.map { String($0) }.joined(separator: " "))"
        }
    }
}

/// Assign BlindBandit call numbers to people (local + iCloud until server API).
struct CallNumberSettingsView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var myNumber: String = CallNumberDirectory.myCallNumber
    @State private var draftNumbers: [String: String] = [:]

    var body: some View {
        Form {
            Section {
                TextField("Your BlindBandit number", text: $myNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .accessibilityIdentifier("my-call-number")
                    .onChange(of: myNumber) { _, v in
                        CallNumberDirectory.myCallNumber = v
                    }
            } header: {
                Text("My call number")
            } footer: {
                Text("People can dial this from the Dialer once they assign it to your handle. Saved on this iPhone and iCloud Key-Value until server sync ships.")
            }

            Section("People") {
                let handles = communications.conversations.compactMap(\.other?.handle)
                let unique = Array(Set(handles)).sorted()
                if unique.isEmpty {
                    Text("No conversations yet — open a chat first, then assign a number here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(unique, id: \.self) { handle in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(handle)").font(.body)
                                if let n = CallNumberDirectory.number(forHandle: handle) {
                                    Text("Dial \(n)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            TextField("Number", text: Binding(
                                get: {
                                    draftNumbers[handle]
                                        ?? CallNumberDirectory.number(forHandle: handle)
                                        ?? ""
                                },
                                set: { draftNumbers[handle] = $0 }
                            ))
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                            .onSubmit {
                                if let v = draftNumbers[handle] {
                                    CallNumberDirectory.assign(number: v, handle: handle)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !CallNumberDirectory.allAssignments.isEmpty {
                Section("Assigned") {
                    ForEach(CallNumberDirectory.allAssignments, id: \.number) { row in
                        LabeledContent(row.number, value: "@\(row.handle)")
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    CallNumberDirectory.unassign(number: row.number)
                                }
                            }
                    }
                }
            }

            Section {
                Button("Save assignments") {
                    for (handle, number) in draftNumbers where !number.isEmpty {
                        CallNumberDirectory.assign(number: number, handle: handle)
                    }
                    CallNumberDirectory.myCallNumber = myNumber
                    AppHaptics.success()
                    UIAccessibility.post(notification: .announcement, argument: "Call numbers saved")
                }
            }
        }
        .navigationTitle("Call numbers")
        .onAppear {
            myNumber = CallNumberDirectory.myCallNumber
        }
    }
}
