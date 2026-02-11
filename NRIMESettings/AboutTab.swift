import SwiftUI

struct AboutTab: View {
    private let githubURL = "https://github.com/NR2BJ/NRIME"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("NRIME")
                .font(.largeTitle.bold())

            Text("All-in-One Input Method")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("v1.0.0")
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)

            Divider()
                .frame(maxWidth: 200)

            Text("Korean / English / Japanese")
                .font(.body)

            Link(destination: URL(string: githubURL)!) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("GitHub")
                }
                .font(.body)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
