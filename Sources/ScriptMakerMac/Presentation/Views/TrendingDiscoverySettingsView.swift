import SwiftUI

struct TrendingDiscoverySettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRENDING HASHTAGS").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
            Picker("Platform", selection: $viewModel.draftTrendingSettings.platform) {
                ForEach(TrendPlatform.allCases, id: \.self) { platform in Text(platform.title).tag(platform) }
            }
            HStack {
                Text("Results per fetch")
                TextField("Count", value: $viewModel.draftTrendingSettings.resultLimit, format: .number).frame(width: 60)
                Stepper("", value: $viewModel.draftTrendingSettings.resultLimit, in: 1...100).labelsHidden()
            }
            HStack {
                Text("Trend window (hours)")
                TextField("Hours", value: $viewModel.draftTrendingSettings.timeWindowHours, format: .number)
            }
            HStack {
                Text("Cache duration (hours)")
                TextField("Hours", value: $viewModel.trendingCacheHours, format: .number)
            }
            TextField("Region code, e.g. IN", text: $viewModel.draftTrendingSettings.region)
            TextField("Feed language code, e.g. en", text: $viewModel.draftTrendingSettings.feedLanguage)
            Text("Include languages").font(.callout.weight(.medium))
            ForEach(TrendLanguage.allCases, id: \.self) { language in
                Toggle(language.title, isOn: Binding(
                    get: { viewModel.draftTrendingSettings.languages.contains(language) },
                    set: { viewModel.setTrendLanguage(language, enabled: $0) }))
            }
            TextField("Twitter / X endpoint", text: $viewModel.draftTrendingSettings.twitterEndpoint)
            TextField("Instagram endpoint", text: $viewModel.draftTrendingSettings.instagramEndpoint)
            TextField("YouTube endpoint (optional)", text: $viewModel.draftTrendingSettings.youtubeEndpoint)
            Text("Defaults: Google Trends, 15 results, 24-hour window, 6-hour cache, India, English/Hindi/Hinglish. Twitter / X and Instagram require an endpoint. Set a duration to 0 to disable it.")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Button("Save trending settings") { viewModel.saveTrendingSettings() }
            if let error = viewModel.trendingSettingsError { Text(error).foregroundStyle(AppTheme.danger) }
            if let notice = viewModel.trendingSettingsNotice { Text(notice).foregroundStyle(AppTheme.secondaryInk) }
        }
        .textFieldStyle(.roundedBorder)
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
    }
}
