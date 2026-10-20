import SwiftUI

struct LibraryUploadSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UPLOADS").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
            Text("Telegram").font(.headline)
            SecureField("Bot token", text: $viewModel.uploadOptions.telegramToken)
            TextField("Chat ID", text: $viewModel.uploadOptions.telegramChatID)
            Toggle("Also send to configured Telegram groups", isOn: $viewModel.uploadOptions.includeTelegramGroups)
            Text("Leave token and chat ID blank to use your existing Telegram bot setup.")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Divider()
            Text("Google Drive / Sheets").font(.headline)
            SecureField("Google access token (optional)", text: $viewModel.uploadOptions.googleAccessToken)
            TextField("Apps Script deployment URL (optional)", text: $viewModel.uploadOptions.googleEndpoint)
            Text("Leave blank to use your existing Google sign-in and default upload destination.")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Text("Saved securely in Keychain. Upload actions use these settings without asking again.")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            HStack {
                Button("Save upload settings") { viewModel.saveUploadSettings() }
                    .disabled(!viewModel.canSaveUploadSettings)
                if !viewModel.canSaveUploadSettings {
                    Button("Reload") { viewModel.loadUploadSettings() }
                }
            }
            if let error = viewModel.uploadSettingsError { Text(error).foregroundStyle(AppTheme.danger) }
            if let notice = viewModel.uploadSettingsNotice { Text(notice).foregroundStyle(AppTheme.secondaryInk) }
        }
        .textFieldStyle(.roundedBorder)
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
    }
}
