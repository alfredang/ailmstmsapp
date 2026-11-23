import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Trainer announcements on the class page, through the website's own routes:
//   POST   /api/trainer/create-announcement   (multipart: courseRunId, postedBy, message, file)
//   DELETE /api/course/announcements?id=       (class trainer only)
// Attachments go to the class's Google Drive folder, shared view-only, as on the website.

/// The trainer's composer: a message, an optional photo or file, then Post.
struct AnnouncementComposer: View {
  @EnvironmentObject var store: Store
  let runID: String
  let posted: () -> Void
  @State private var message = ""
  @State private var attachment: (data: Data, name: String, mime: String)?
  @State private var photo: PhotosPickerItem?
  @State private var picking = false
  @State private var posting = false
  @State private var problem: String?

  static let maxBytes = 50 * 1024 * 1024

  private var canPost: Bool {
    !posting && (!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Write an announcement for this class…", text: $message, axis: .vertical)
        .lineLimit(3...8)
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("announcement-text")
      if let attachment {
        HStack {
          Label(attachment.name, systemImage: attachment.mime.hasPrefix("image/") ? "photo" : "paperclip")
            .font(.subheadline).lineLimit(1).truncationMode(.middle)
          Spacer()
          Button {
            self.attachment = nil
            photo = nil
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.borderless).accessibilityLabel("Remove attachment")
        }
      }
      HStack(spacing: 10) {
        PhotosPicker(selection: $photo, matching: .images) {
          Label("Photo", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(.bordered).accessibilityIdentifier("announcement-photo")
        Button {
          picking = true
        } label: {
          Label("File", systemImage: "paperclip")
        }
        .buttonStyle(.bordered).accessibilityIdentifier("announcement-file")
        Spacer()
        Button {
          Task { await post() }
        } label: {
          Text(posting ? "Posting…" : "Post").font(.headline).padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(!canPost)
        .accessibilityIdentifier("announcement-post")
      }
      if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
    }
    .padding(.vertical, 4)
    .onChange(of: photo) { _, item in
      guard let item else { return }
      Task { await loadPhoto(item) }
    }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
      guard case .success(let url) = result else { return }
      loadFile(url)
    }
  }

  private func loadPhoto(_ item: PhotosPickerItem) async {
    guard let data = try? await item.loadTransferable(type: Data.self) else {
      problem = "That photo could not be read. Please choose another."
      return
    }
    // Photos are sent as JPEG so every device can open them.
    let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
    guard jpeg.count <= Self.maxBytes else {
      problem = "That photo is larger than 50 MB."
      return
    }
    let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
    attachment = (jpeg, "Photo \(stamp).jpg", "image/jpeg")
    problem = nil
  }

  private func loadFile(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else {
      problem = "That file could not be read."
      return
    }
    guard data.count <= Self.maxBytes else {
      problem = "That file is larger than 50 MB. Upload a smaller file, or paste a link to it in the message."
      return
    }
    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    attachment = (data, url.lastPathComponent, mime)
    photo = nil
    problem = nil
  }

  private func post() async {
    if store.demo {
      problem = "Posting is available when you sign in with your account."
      return
    }
    posting = true
    defer { posting = false }
    var fields = ["courseRunId": runID, "postedBy": store.profile?.fullName ?? store.user?.fullName ?? "Trainer"]
    let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { fields["message"] = text }
    do {
      let _: EmptyReply = try await API.shared.multipart(
        "trainer/create-announcement", fields: fields, file: attachment)
      message = ""
      attachment = nil
      photo = nil
      problem = nil
      posted()
    } catch { problem = error.localizedDescription }
  }
}

/// The trainer's delete control on one announcement.
struct AnnouncementDeleteButton: View {
  @EnvironmentObject var store: Store
  let id: String
  let deleted: () -> Void
  @State private var confirming = false
  @State private var problem: String?
  var body: some View {
    Button(role: .destructive) {
      confirming = true
    } label: {
      Label("Delete", systemImage: "trash").font(.caption)
    }
    .buttonStyle(.borderless)
    .confirmationDialog("Delete this post?", isPresented: $confirming, titleVisibility: .visible) {
      Button("Delete post", role: .destructive) { Task { await delete() } }
    } message: {
      Text("Learners will no longer see it. An attached file stays in the class's Drive folder.")
    }
    if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
  }
  private func delete() async {
    if store.demo { return }
    do {
      let _: EmptyReply = try await API.shared.request(
        "course/announcements", method: "DELETE", query: ["id": id])
      deleted()
    } catch { problem = error.localizedDescription }
  }
}
