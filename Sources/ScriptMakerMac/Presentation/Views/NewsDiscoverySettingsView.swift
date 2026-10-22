import SwiftUI

struct NewsDiscoverySettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEWS DISCOVERY").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(AppTheme.secondaryInk)
            Text("Shared by Studio and Library.").font(.callout).foregroundStyle(AppTheme.secondaryInk)
            HStack {
                Text("Results per fetch")
                TextField("Count", value: $viewModel.newsPageSize, format: .number).frame(width: 60)
                Stepper("", value: $viewModel.newsPageSize, in: 1...100).labelsHidden()
            }
            HStack {
                Text("Search window (hours)")
                TextField("Hours", value: $viewModel.newsSearchHours, format: .number)
            }
            HStack {
                Text("Cache duration (hours)")
                TextField("Hours", value: $viewModel.newsCacheHours, format: .number)
            }
            Picker("RSS providers", selection: $viewModel.draftNewsSettings.providerOrder) {
                ForEach(NewsFeedOrder.allCases, id: \.self) { order in Text(order.rawValue).tag(order) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Region / Geo")
                    TextField("Country or code (e.g. India, IN, United States, US)", text: $viewModel.newsRegionGeoText)
                }
                if let geo = RegionGeo.resolve(viewModel.newsRegionGeoText) {
                    Text("\(geo.flag) \(geo.name) · Geo Code: \(geo.code)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                } else if !viewModel.newsRegionGeoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("⚠️ Not a recognized country or region geo. Cities and states are not supported.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                }
            }
            TextField("Language code, e.g. en", text: $viewModel.draftNewsSettings.language)
            Text("Defaults: India (IN), 20 results, 24-hour search window, 6-hour cache, Google then Bing, en. Set a duration to 0 to disable its filter or cache. Refresh always fetches fresh news.")
                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            Button("Save news settings") { viewModel.saveNewsSettings() }
            if let error = viewModel.newsSettingsError { Text(error).foregroundStyle(AppTheme.danger) }
            if let notice = viewModel.newsSettingsNotice { Text(notice).foregroundStyle(AppTheme.secondaryInk) }
        }
        .textFieldStyle(.roundedBorder)
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
    }
}
