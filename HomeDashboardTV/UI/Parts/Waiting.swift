import SwiftUI

/// Until the first snapshot: reading, or what went wrong and what to do about it.
struct Waiting: View {
    let problem: String?
    let hint: String

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
            Text(problem ?? "Reading the dashboard…")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            if problem != nil {
                Text(hint)
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
