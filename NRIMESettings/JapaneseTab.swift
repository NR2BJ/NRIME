import SwiftUI

struct JapaneseTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "character.ja")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Japanese Input Settings")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Japanese engine (Mozc) will be available in Phase 4.")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
