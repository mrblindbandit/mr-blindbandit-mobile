import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import Intents

// MARK: - Shared public profile avatar

/// Public social `avatar_url` photo (HTTPS). Initials when missing or unloadable.
/// Accessibility uses the display name — never "image".
struct ProfileAvatar: View {
    let urlString: String?
    let displayName: String
    var size: CGFloat = 44
    var verified: Bool = false
    var decorative: Bool = true

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        if !letters.isEmpty { return letters.uppercased() }
        return String(displayName.prefix(2)).uppercased()
    }

    private var url: URL? {
        guard let s = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              let u = URL(string: s), u.scheme == "https" else { return nil }
        return u
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(Brand.gold.opacity(0.3))
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            initialsView
                        case .empty:
                            ProgressView().controlSize(.small)
                        @unknown default:
                            initialsView
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                } else {
                    initialsView
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            if verified {
                VerifiedBadge()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(decorative ? "" : displayName + (verified ? ", Verified" : ""))
        .accessibilityHidden(decorative)
    }

    private var initialsView: some View {
        Group {
            if initials.isEmpty {
                Image(systemName: "person.fill").font(.system(size: size * 0.4))
            } else {
                Text(initials).font(.system(size: size * 0.36, weight: .semibold))
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Image prep (square JPEG ~512–1024)

enum ProfilePhotoPrep {
    static let maxEdge: CGFloat = 768
    static let jpegQuality: CGFloat = 0.82
    static let maxBytes = 900_000

    static func jpegData(from image: UIImage) -> Data? {
        let squared = squareCrop(image)
        let scaled = resize(squared, maxEdge: maxEdge)
        var quality = jpegQuality
        var data = scaled.jpegData(compressionQuality: quality)
        while let d = data, d.count > maxBytes, quality > 0.4 {
            quality -= 0.1
            data = scaled.jpegData(compressionQuality: quality)
        }
        return data
    }

    static func squareCrop(_ image: UIImage) -> UIImage {
        let raw = image.fixedOrientation()
        let side = min(raw.size.width, raw.size.height)
        guard side > 0 else { return raw }
        let origin = CGPoint(x: (raw.size.width - side) / 2, y: (raw.size.height - side) / 2)
        let rect = CGRect(origin: origin, size: CGSize(width: side, height: side))
        guard let cg = raw.cgImage?.cropping(to: rect.integralScaled(to: raw.scale)) else { return raw }
        return UIImage(cgImage: cg, scale: raw.scale, orientation: .up)
    }

    static func resize(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Builds an INImage for CallKit / Intents when a public avatar URL is already cached lightly.
    static func intentImage(from urlString: String?) async -> INImage? {
        guard let s = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              let url = URL(string: s), url.scheme == "https" else { return nil }
        if let cached = AvatarImageCache.data(for: s) {
            return INImage(imageData: cached)
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count > 32, data.count < 2_000_000 else { return nil }
            AvatarImageCache.put(data, for: s)
            return INImage(imageData: data)
        } catch {
            return nil
        }
    }
}

private extension CGRect {
    func integralScaled(to scale: CGFloat) -> CGRect {
        CGRect(x: origin.x * scale, y: origin.y * scale, width: size.width * scale, height: size.height * scale)
    }
}

private extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - Light in-memory cache

enum AvatarImageCache {
    private static let lock = NSLock()
    private static var store: [String: Data] = [:]
    private static let maxEntries = 40

    static func data(for key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return store[key]
    }

    static func put(_ data: Data, for key: String) {
        lock.lock(); defer { lock.unlock() }
        if store.count >= maxEntries, let first = store.keys.first { store.removeValue(forKey: first) }
        store[key] = data
    }

    static func clear(_ key: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let key { store.removeValue(forKey: key) } else { store.removeAll() }
    }
}

// MARK: - Settings: set / remove public profile picture

struct ProfilePictureEditor: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var busy = false
    @State private var status = ""
    @State private var confirmRemove = false
    @State private var localPreview: UIImage?

    private var hasPhoto: Bool {
        localPreview != nil || !(communications.myAvatarURL ?? "").isEmpty
    }

    var body: some View {
        Section {
            HStack(spacing: 16) {
                if let localPreview {
                    Image(uiImage: localPreview)
                        .resizable().scaledToFill()
                        .frame(width: 72, height: 72).clipShape(Circle())
                        .accessibilityHidden(true)
                } else {
                    ProfileAvatar(
                        urlString: communications.myAvatarURL,
                        displayName: communications.myDisplayName.isEmpty ? "You" : communications.myDisplayName,
                        size: 72,
                        verified: false,
                        decorative: true
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile picture").font(.headline)
                    Text(hasPhoto ? "Visible to contacts and anyone who can see your profile." : "No photo yet. Initials show until you add one.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(hasPhoto ? "Profile picture set" : "No profile picture")

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(busy ? "Uploading…" : "Choose from Photos", systemImage: "photo.on.rectangle")
            }
            .disabled(busy)
            .accessibilityHint("Picks a photo from your library, then uploads it as your public profile picture.")

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera")
                }
                .disabled(busy)
            }

            if hasPhoto {
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("Remove photo", systemImage: "trash")
                }
                .disabled(busy)
            }

            if !status.isEmpty {
                Text(status).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel(status)
            }
        } header: {
            Text("Profile picture")
        } footer: {
            Text("This photo is public on your Blindbandit profile. Contacts and people who can view your profile can see it. It is not end-to-end encrypted.")
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await pick(item) }
        }
        .confirmationDialog("Remove your profile picture?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove photo", role: .destructive) { Task { await remove() } }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            ProfileCameraCapture { image in
                showCamera = false
                Task { await upload(image) }
            } onCancel: { showCamera = false }
            .ignoresSafeArea()
        }
    }

    private func announce(_ text: String) {
        status = text
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func pick(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false; pickerItem = nil }
        announce("Loading photo")
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                announce("Could not read that photo. Try another.")
                return
            }
            await upload(image)
        } catch {
            announce("Could not open that photo. \(error.localizedDescription)")
        }
    }

    private func upload(_ image: UIImage) async {
        busy = true
        defer { busy = false }
        localPreview = image
        announce("Uploading profile picture")
        guard let jpeg = ProfilePhotoPrep.jpegData(from: image) else {
            localPreview = nil
            announce("Could not prepare that photo. Try another.")
            return
        }
        do {
            let url = try await BlindbanditAPI.uploadPublicAvatar(jpeg: jpeg)
            await MainActor.run {
                communications.applyMyAvatarURL(url)
                AvatarImageCache.clear()
            }
            announce("Profile picture updated. Others can see it.")
        } catch {
            localPreview = nil
            announce("Could not upload profile picture. \(error.localizedDescription)")
        }
    }

    private func remove() async {
        busy = true
        defer { busy = false }
        announce("Removing profile picture")
        do {
            try await BlindbanditAPI.clearPublicAvatar()
            await MainActor.run {
                localPreview = nil
                communications.applyMyAvatarURL(nil)
                AvatarImageCache.clear()
            }
            announce("Profile picture removed. Initials will show instead.")
        } catch {
            announce("Could not remove profile picture. \(error.localizedDescription)")
        }
    }
}

/// Minimal camera capture for profile photos (VoiceOver-friendly cancel / use).
struct ProfileCameraCapture: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileCameraCapture
        init(_ parent: ProfileCameraCapture) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onCapture(img)
            } else {
                parent.onCancel()
            }
        }
    }
}
