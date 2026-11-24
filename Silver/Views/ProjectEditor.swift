import SwiftUI
import UniformTypeIdentifiers

struct ProjectEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State var project: Project
    var isAdding = false
    @State private var imageData: Data?
    @State private var showImagePicker = false
    @State private var imageError: String?
    var body: some View {
        VStack(spacing: 22) {
            AnimatedProjectIcon(symbol: project.symbol, color: project.color, size: 64, image: imageData.flatMap(NSImage.init(data:)) ?? ProjectIconStorage.image(project.iconFile)).frame(width: 64, height: 64)
            Text(isAdding ? "Add Project" : "Customise Project").font(.title2.bold())
            Form {
                TextField("Name", text: $project.name)
                LabeledContent("Colour") { ColorChoices(selection: $project.color) }
                LabeledContent("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 6), spacing: 8) {
                        ForEach(Project.symbols, id: \.self) { symbol in
                            Button { project.symbol = symbol; project.iconFile = nil; imageData = nil } label: {
                                Image(systemName: symbol).frame(width: 28, height: 28)
                            }.buttonStyle(.bordered).tint(project.symbol == symbol && project.iconFile == nil && imageData == nil ? project.color.color : .secondary)
                                .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                                .accessibilityAddTraits(project.symbol == symbol && project.iconFile == nil && imageData == nil ? .isSelected : [])
                        }
                    }
                }
                LabeledContent("Image") {
                    HStack {
                        Button("Choose Image…") { showImagePicker = true }
                        if imageData != nil || project.iconFile != nil {
                            Button("Remove") { imageData = nil; project.iconFile = nil }
                        }
                    }
                }
            }.formStyle(.grouped)
            if let imageError { Text(imageError).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(isAdding ? "Add Project" : "Save") {
                    do {
                        if let imageData { project.iconFile = try ProjectIconStorage.save(imageData) }
                        project.name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if isAdding { library.add(project) } else { library.update(project) }
                        dismiss()
                    } catch { imageError = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
                    .disabled(project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 480, height: 560)
        .fileImporter(isPresented: $showImagePicker, allowedContentTypes: [.image]) { result in
            do { imageData = try ProjectIconStorage.thumbnail(from: result.get()); imageError = nil }
            catch { imageError = error.localizedDescription }
        }
    }
}

struct ColorChoices: View {
    @Binding var selection: ProjectColor
    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProjectColor.allCases) { color in
                Button { selection = color } label: {
                    ZStack {
                        Circle().fill(color.color).frame(width: 20, height: 20)
                        if color == selection { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                    }.frame(width: 24, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).help(color.name).accessibilityLabel(color.name)
                    .accessibilityAddTraits(color == selection ? .isSelected : [])
            }
        }
    }
}
