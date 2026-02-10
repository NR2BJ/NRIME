import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("NRIME")
                .font(.largeTitle.bold())

            Text("All-in-One Input Method")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("v0.1.0")
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)

            Divider()
                .frame(maxWidth: 200)

            VStack(spacing: 8) {
                Text("Korean / English / Japanese")
                    .font(.body)
                Text("Single input source. Zero delay switching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("Shortcuts")
                    .font(.headline)
                HStack(spacing: 16) {
                    VStack {
                        Text("Right Shift")
                            .font(.caption.bold())
                        Text("Toggle EN")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Text("Right Shift + 1")
                            .font(.caption.bold())
                        Text("Korean")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Text("Right Shift + 2")
                            .font(.caption.bold())
                        Text("Japanese")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
