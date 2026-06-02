
import SwiftUI

public struct LogTabView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var filterText = ""

    private var filteredLogs: [LogEntry] {
        if filterText.isEmpty { return labVM.logEntries }
        return labVM.logEntries.filter {
            $0.message.localizedCaseInsensitiveContains(filterText)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(themeVM.accent.opacity(0.5))
                    .font(.caption)
                TextField("Filter logs...", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    labVM.logEntries.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.5))
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.4))

            // Log entries
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredLogs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timeString)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(themeVM.accent.opacity(0.5))
                                .frame(width: 55, alignment: .leading)
                            Text(entry.message)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.02))
                    }

                    if filteredLogs.isEmpty {
                        Text(filterText.isEmpty ? "No log entries." : "No matches.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.3))
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
            }

            // Stats bar
            HStack {
                Text("\(labVM.logEntries.count) entries")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                Text("ArcLake v1.45")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.4))
        }
    }
}
