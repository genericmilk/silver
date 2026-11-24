import SwiftUI

struct EditorSettings: View {
    @Environment(Preferences.self) private var preferences
    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("Code") {
                Picker("Font", selection: $preferences.layout.codeFont) {
                    ForEach(["SF Mono", "Menlo", "Monaco", "Courier"], id: \.self) { Text($0).tag($0) }
                }
                Stepper("Font size: \(Int(preferences.layout.codeSize)) pt", value: $preferences.layout.codeSize, in: 10...22, step: 1)
                Stepper("Line spacing: \(Int(preferences.layout.codeLineSpacing)) pt", value: $preferences.layout.codeLineSpacing, in: 0...8, step: 1)
                Toggle("Wrap long lines", isOn: $preferences.layout.wrapLines)
            }
            Section("Diffs") {
                Picker("Layout", selection: $preferences.diffStyle) {
                    Text("Inline").tag("inline")
                    Text("Side by Side").tag("split")
                }
                Toggle("Show line numbers", isOn: $preferences.lineNumbers)
                Picker("Colours", selection: $preferences.layout.diffPalette) {
                    Text("Green & Red").tag("classic")
                    Text("Teal & Pink").tag("accessible")
                    Text("Monochrome").tag("subtle")
                }
                Toggle("Highlight changed line backgrounds", isOn: $preferences.layout.diffBackgrounds)
                Picker("Context around changes", selection: $preferences.layout.contextLines) {
                    ForEach([0, 3, 5, 10], id: \.self) { Text("\($0) lines").tag($0) }
                }
                Toggle("Expand unchanged context by default", isOn: $preferences.layout.expandContext)
                VStack(alignment: .leading, spacing: preferences.layout.codeLineSpacing) {
                    Text("− let greeting = \"Hello\"").foregroundStyle(Color(nsColor: preferences.layout.deletionColor))
                        .background(preferences.layout.diffBackgrounds ? Color(nsColor: preferences.layout.deletionColor).opacity(0.07) : .clear)
                    Text("+ let greeting = \"Hello, Silver\"").foregroundStyle(Color(nsColor: preferences.layout.additionColor))
                        .background(preferences.layout.diffBackgrounds ? Color(nsColor: preferences.layout.additionColor).opacity(0.07) : .clear)
                }.font(Font(preferences.layout.codeNSFont)).padding(.vertical, 8)
            }
            Section("Commit Editor") {
                Stepper("Description height: \(Int(preferences.layout.commitEditorHeight)) pt", value: $preferences.layout.commitEditorHeight, in: 60...160, step: 20)
            }
        }.formStyle(.grouped)
    }
}
