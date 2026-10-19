import SwiftUI

struct LibraryUploadView: View {
    let story: Story
    let destination: LibraryUploadDestination
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(destination == .telegram ? "Upload to Telegram" : "Upload to Google Drive / Sheets")
                .font(.title2.weight(.semibold))
            Text(story.title).font(.headline)
            if destination == .telegram {
                Text("Sends the title and hashtags, optional video, then news links. Uses the same bot files and saved chat ID as ScriptMaker.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
                SecureField("Bot token (optional override when no token file exists)", text: $viewModel.uploadOptions.telegramToken)
                TextField("Chat ID (optional when already saved)", text: $viewModel.uploadOptions.telegramChatID)
                Toggle("Also send to configured and discovered Telegram groups", isOn: $viewModel.uploadOptions.includeTelegramGroups)
                Text("Default token: ~/Documents/telegrambot/bot_token.txt\nGroups: ~/Documents/telegrambot/group_ids.txt")
                    .font(.caption).foregroundStyle(AppTheme.secondaryInk).textSelection(.enabled)
            } else {
                Text("Uploads the attached video to Drive and adds a Google Sheets row, using ScriptMaker’s Khabarwaani Operations endpoint. Title, hashtags and news links accompany the video.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryInk)
                if story.videoURL == nil {
                    Label("Attach a video using Add video before uploading.", systemImage: "video.badge.plus")
                }
                Text("Uses your existing clasp login or GOOGLE_ACCESS_TOKEN. To sign in, run npx clasp login in Terminal.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                SecureField("Google access token (optional when already signed in)", text: $viewModel.uploadOptions.googleAccessToken)
                TextField("Apps Script endpoint (optional override)", text: $viewModel.uploadOptions.googleEndpoint)
                if let receipt = story.uploadReceipt {
                    Text("Previously uploaded · row \(receipt.id) · \(receipt.uploadedAt)").font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(StudioButtonStyle())
                Button("Upload") {
                    let snapshot = story
                    Task { await viewModel.upload(snapshot, to: destination) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(StudioPrimaryButtonStyle())
                    .disabled(viewModel.isUploading || (destination == .googleSheets && (story.videoURL ?? "").isEmpty))
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 580)
        .foregroundStyle(AppTheme.ink).background(AppTheme.card)
    }
}
