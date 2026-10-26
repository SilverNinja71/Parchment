import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Drawing a cover

/// A notebook cover: photo, Cover Library design, or color + material, with a spine
/// and optional elastic band. Drawn in code so it's crisp at every size.
struct NotebookCoverView: View {
    let appearance: CoverAppearance
    var title: String?
    var showsBand = false
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                background(size)
                if appearance.image == nil {
                    Canvas { context, size in
                        if let design = appearance.design {
                            CoverArtist.draw(art: design.art, accent: Color(hex: design.accent), in: &context, size: size)
                        }
                        CoverArtist.draw(material: appearance.design?.material ?? appearance.material, in: &context, size: size)
                    }
                    doodle
                    stamp(size)
                }
                spine(size)
                if showsBand { band(size) }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func background(_ size: CGSize) -> some View {
        if let image = appearance.image {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
        } else if let design = appearance.design {
            LinearGradient(colors: design.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            let base = Color(hex: appearance.colorHex)
            LinearGradient(colors: [base.opacity(0.88), base], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(Color.black)
        }
    }

    @ViewBuilder
    private var doodle: some View {
        if appearance.design == nil, appearance.material == .kitDoodle,
           let index = appearance.customCover ?? theme.availableCovers.first, let image = theme.cover(index) {
            Image(uiImage: image).resizable().scaledToFill()
        }
    }

    /// Foil symbol and the notebook title, in the design's style.
    @ViewBuilder
    private func stamp(_ size: CGSize) -> some View {
        let design = appearance.design
        let accent = Color(hex: design?.accent ?? "FFFFFF")
        let style = design?.titleStyle ?? .minimal
        VStack(spacing: size.height * 0.03) {
            if let foil = design?.foil {
                Image(systemName: foil)
                    .font(.system(size: size.width * 0.16, weight: .light))
                    .foregroundStyle(accent.opacity(0.9))
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
            }
            if let title, style != .minimal {
                Text(title)
                    .font(.system(size: max(8, size.width * 0.085), weight: .semibold, design: .serif))
                    .foregroundStyle(style == .label ? Color(hex: "2B2620") : accent)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .padding(.horizontal, size.width * 0.06).padding(.vertical, size.width * 0.03)
                    .background {
                        if style == .label {
                            RoundedRectangle(cornerRadius: 3).fill(accent)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                        }
                    }
            }
        }
        .frame(width: size.width * 0.8)
        .position(x: size.width * 0.54, y: size.height * 0.36)

        if let title, style == .minimal {
            Text(title)
                .font(.system(size: max(7, size.width * 0.07), weight: .medium, design: .serif))
                .foregroundStyle(design.map { Color(hex: $0.accent) } ?? .white.opacity(0.92))
                .lineLimit(1)
                .padding(.leading, size.width * 0.14)
                .frame(width: size.width, height: size.height, alignment: .bottomLeading)
                .padding(.bottom, size.height * 0.06)
        }
    }

    /// Darker binding with stitching, like a sewn notebook.
    private func spine(_ size: CGSize) -> some View {
        let width = max(6, size.width * 0.075)
        let color = appearance.design.map { Color(hex: $0.spine) } ?? Color.black.opacity(0.22)
        return ZStack {
            Rectangle().fill(appearance.design == nil ? color : color.opacity(0.9))
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: max(0.5, width * 0.06), dash: [max(2, width * 0.35), max(2, width * 0.3)]))
                .foregroundStyle(.white.opacity(0.28))
                .frame(width: 0.5)
                .offset(x: width * 0.2)
        }
        .frame(width: width, height: size.height)
        .overlay(alignment: .trailing) { Rectangle().fill(.black.opacity(0.18)).frame(width: 0.75) }
    }

    /// Moleskine-style elastic band.
    private func band(_ size: CGSize) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.35), .black.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
            .frame(width: max(4, size.width * 0.035), height: size.height)
            .offset(x: size.width * 0.86)
    }
}

/// Procedural textures and artwork for covers.
enum CoverArtist {
    static func draw(material: CoverMaterial, in context: inout GraphicsContext, size: CGSize) {
        switch material {
        case .smooth, .kitDoodle:
            break
        case .leather:
            // Fine grain speckle plus a soft vignette.
            var random = SeededRandom(seed: 7)
            for _ in 0..<Int(size.width * size.height / 30) {
                let point = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
                let dot = CGRect(x: point.x, y: point.y, width: 1, height: 1)
                context.fill(Path(ellipseIn: dot), with: .color(random.next() > 0.5 ? .white.opacity(0.05) : .black.opacity(0.08)))
            }
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.28)]),
                                               center: CGPoint(x: size.width / 2, y: size.height / 2),
                                               startRadius: min(size.width, size.height) * 0.3,
                                               endRadius: max(size.width, size.height) * 0.75))
        case .linen:
            var path = Path()
            stride(from: 0, through: size.height, by: 2.5).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
            stride(from: 0, through: size.width, by: 2.5).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
            context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
        case .gridEmboss:
            var path = Path()
            let step = max(8, size.width / 12)
            stride(from: 0, through: size.height, by: step).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
            stride(from: 0, through: size.width, by: step).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
            context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 0.6)
        case .geometric:
            var path = Path()
            let step = size.width / 4
            for row in 0...Int(size.height / step) {
                for column in 0...4 {
                    let origin = CGPoint(x: CGFloat(column) * step, y: CGFloat(row) * step)
                    path.move(to: origin)
                    path.addLine(to: CGPoint(x: origin.x + step, y: origin.y + step))
                    path.move(to: CGPoint(x: origin.x + step, y: origin.y))
                    path.addLine(to: CGPoint(x: origin.x, y: origin.y + step))
                }
            }
            context.stroke(path, with: .color(.white.opacity(0.14)), lineWidth: 0.8)
        }
    }

    static func draw(art: CoverArt, accent: Color, in context: inout GraphicsContext, size: CGSize) {
        var random = SeededRandom(seed: 42)
        switch art {
        case .none:
            break
        case .watercolor:
            let washes: [Color] = [Color(hex: "8FC1E3"), Color(hex: "F4A7B9"), Color(hex: "F9D77E"), Color(hex: "A8D8B9")]
            for (index, color) in washes.enumerated() {
                let radius = size.width * (0.35 + random.next() * 0.25)
                let center = CGPoint(x: size.width * (0.25 + 0.5 * random.next()), y: size.height * (0.2 + 0.6 * CGFloat(index) / 3))
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.8, width: radius * 2, height: radius * 1.6)),
                             with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                                                   center: center, startRadius: 0, endRadius: radius))
            }
        case .blueprint:
            var minor = Path(), major = Path()
            let step = size.width / 16
            for index in 0...Int(max(size.width, size.height) / step) {
                let value = CGFloat(index) * step
                var target = index % 4 == 0 ? major : minor
                target.move(to: CGPoint(x: value, y: 0)); target.addLine(to: CGPoint(x: value, y: size.height))
                target.move(to: CGPoint(x: 0, y: value)); target.addLine(to: CGPoint(x: size.width, y: value))
                if index % 4 == 0 { major = target } else { minor = target }
            }
            context.stroke(minor, with: .color(.white.opacity(0.12)), lineWidth: 0.4)
            context.stroke(major, with: .color(.white.opacity(0.25)), lineWidth: 0.7)
            context.stroke(Path(ellipseIn: CGRect(x: size.width * 0.45, y: size.height * 0.55, width: size.width * 0.4, height: size.width * 0.4)),
                           with: .color(.white.opacity(0.4)), lineWidth: 0.8)
        case .marble:
            for index in 0..<9 {
                var vein = Path()
                var point = CGPoint(x: -10, y: size.height * CGFloat(index) / 8)
                vein.move(to: point)
                while point.x < size.width + 10 {
                    point = CGPoint(x: point.x + size.width / 6, y: point.y + (random.next() - 0.45) * size.height * 0.12)
                    vein.addQuadCurve(to: point, control: CGPoint(x: point.x - size.width / 12, y: point.y + (random.next() - 0.5) * 30))
                }
                context.stroke(vein, with: .color(Color(hex: index % 2 == 0 ? "8C6E52" : "B9A58C").opacity(0.45)), lineWidth: 0.6 + random.next() * 1.4)
            }
        case .carbon:
            let step: CGFloat = 4
            for row in 0...Int(size.height / step) {
                for column in 0...Int(size.width / step) {
                    let rect = CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step, height: step)
                    let light = (row + column) % 2 == 0
                    context.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: [.white.opacity(light ? 0.07 : 0.0), .black.opacity(light ? 0.0 : 0.15)]),
                        startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                }
            }
        case .triangles:
            for _ in 0..<14 {
                let a = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
                var path = Path()
                path.move(to: a)
                path.addLine(to: CGPoint(x: a.x + (random.next() - 0.5) * size.width * 0.6, y: a.y + random.next() * size.height * 0.3))
                path.addLine(to: CGPoint(x: a.x + (random.next() - 0.5) * size.width * 0.6, y: a.y - random.next() * size.height * 0.3))
                path.closeSubpath()
                context.fill(path, with: .color(.white.opacity(0.06 + random.next() * 0.1)))
            }
        case .circles:
            let center = CGPoint(x: size.width * 0.62, y: size.height * 0.42)
            for ring in 1...6 {
                let radius = CGFloat(ring) * size.width * 0.12
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                               with: .color(accent.opacity(0.35 - Double(ring) * 0.04)), lineWidth: 0.7)
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(accent.opacity(0.8)))
        }
    }
}

/// Deterministic randomness, so textures look the same every time they're drawn.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

// MARK: - Live 3D preview

/// A notebook you can tilt with your finger: pages behind the cover, a ribbon and an elastic band.
struct CoverPreview3D: View {
    let appearance: CoverAppearance
    let title: String
    var width: CGFloat = 230
    @State private var tilt = CGSize.zero

    var body: some View {
        let height = width * 4 / 3
        ZStack {
            // Page block peeking out from behind the cover.
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.paper)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.06)))
                    .frame(width: width, height: height)
                    .offset(x: CGFloat(3 - index) * 2.5, y: CGFloat(3 - index) * 1.5)
            }
            NotebookCoverView(appearance: appearance, title: title, showsBand: true)
                .frame(width: width, height: height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12))
                .overlay(alignment: .bottom) {
                    // Bookmark ribbon.
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: 12, y: 0))
                        path.addLine(to: CGPoint(x: 12, y: 30))
                        path.addLine(to: CGPoint(x: 6, y: 23))
                        path.addLine(to: CGPoint(x: 0, y: 30))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: "B3261E"))
                    .frame(width: 12, height: 30)
                    .offset(x: width * 0.22, y: 26)
                }
        }
        .rotation3DEffect(.degrees(Double(-14 + tilt.width / 6)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(Double(4 - tilt.height / 10)), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .shadow(color: .black.opacity(0.18), radius: 18, x: 8, y: 14)
        .gesture(DragGesture()
            .onChanged { tilt = $0.translation }
            .onEnded { _ in withAnimation(Style.spring) { tilt = .zero } })
        .animation(Style.spring, value: appearance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cover preview")
    }
}

// MARK: - Customizer

/// Color, finish, Cover Library and photo covers, with a live preview.
struct CoverCustomizer: View {
    @Binding var appearance: CoverAppearance
    let title: String

    @ObservedObject private var theme = ThemeStore.shared
    @State private var showLibrary = false
    @State private var photo: PhotosPickerItem?
    @State private var importingFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            CoverPreview3D(appearance: appearance, title: title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

            section("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(Notebook.namedPalette, id: \.hex) { swatch in
                        let selected = appearance.design == nil && appearance.image == nil && appearance.colorHex == swatch.hex
                        Button {
                            update { $0.colorHex = swatch.hex; $0.designID = nil; $0.image = nil }
                        } label: {
                            VStack(spacing: 4) {
                                Circle().fill(Color(hex: swatch.hex))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(Color.black.opacity(0.1)))
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(selected ? Style.selection : .clear, lineWidth: 2.5))
                                Text(swatch.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.name)
                    }
                }
            }

            section("Finish") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CoverMaterial.allCases.filter { $0 != .kitDoodle || !theme.availableCovers.isEmpty }) { material in
                            let selected = appearance.design == nil && appearance.image == nil && appearance.material == material
                            Button {
                                update { $0.material = material; $0.designID = nil; $0.image = nil }
                            } label: {
                                Text(material.title)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(selected ? .white : .primary)
                                    .background(selected ? Style.selection : Color.secondary.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if appearance.material == .kitDoodle, appearance.design == nil, theme.availableCovers.count > 1 {
                    HStack {
                        ForEach(theme.availableCovers, id: \.self) { index in
                            Button { update { $0.customCover = index } } label: {
                                Image(uiImage: theme.cover(index) ?? UIImage()).resizable().scaledToFit()
                                    .frame(width: 40, height: 54)
                                    .background(Color.paper, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder((appearance.customCover ?? theme.availableCovers.first) == index ? Style.selection : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            section("More Covers") {
                HStack(spacing: 10) {
                    Button { showLibrary = true } label: {
                        Label("Browse Library", systemImage: "books.vertical").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Photo", systemImage: "photo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { importingFile = true } label: {
                        Label("Files", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if appearance.image != nil {
                    Button("Remove Photo", role: .destructive) { update { $0.image = nil } }
                        .font(.subheadline)
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $showLibrary) {
            CoverLibraryView(title: title, current: appearance.designID) { id in
                update { $0.designID = id; $0.image = nil }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    update { $0.image = image.coverSized() }
                }
                photo = nil
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                update { $0.image = image.coverSized() }
            }
        }
    }

    private func update(_ change: (inout CoverAppearance) -> Void) {
        Style.tap()
        withAnimation(Style.spring) { change(&appearance) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

extension UIImage {
    /// Shrinks a photo to a sensible cover size (keeps notebooks and sync small).
    func coverSized(maxSide: CGFloat = 1200) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// "Customize Cover" for an existing notebook, from the library or the editor.
struct CoverStudioSheet: View {
    let notebookID: UUID
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @State private var appearance = CoverAppearance()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                CoverCustomizer(appearance: $appearance, title: store.notebook(notebookID)?.title ?? "Notebook")
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
            .background(Color.chrome)
            .navigationTitle("Customize Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.bold()
                }
            }
        }
        .wideSheet()
        .onAppear {
            guard !loaded, let notebook = store.notebook(notebookID) else { return }
            loaded = true
            appearance = CoverAppearance(notebook: notebook, store: store)
        }
    }

    private func save() {
        let photo = appearance.image?.jpegData(compressionQuality: 0.85)
        store.setCoverImageData(photo, for: notebookID)
        store.update(notebookID) { appearance.apply(to: &$0) }
        Style.tap()
        dismiss()
    }
}

// MARK: - Cover Library

struct CoverLibraryView: View {
    let title: String
    let current: String?
    var onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: CoverCategory?
    @State private var previewID: String?

    private var designs: [CoverDefinition] {
        category.map { selected in CoverCatalog.all.filter { $0.category == selected } } ?? CoverCatalog.all
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let id = previewID ?? current, let design = CoverCatalog.design(id) {
                        HStack(spacing: 28) {
                            CoverPreview3D(appearance: .design(design.id), title: title, width: 170)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(design.name).font(.system(.title2, design: .serif).bold())
                                Text(design.category.title).foregroundStyle(.secondary)
                                Button {
                                    onApply(design.id)
                                    Style.tap()
                                    dismiss()
                                } label: {
                                    Label("Apply to Notebook", systemImage: "checkmark").bold()
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 8)
                            }
                            Spacer()
                        }
                        .padding(24)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Style.cardRadius))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            pill("All", selected: category == nil) { category = nil }
                            ForEach(CoverCategory.allCases) { item in
                                pill(item.title, selected: category == item) { category = item }
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 20)], spacing: 22) {
                        ForEach(designs) { design in
                            let selected = (previewID ?? current) == design.id
                            Button {
                                Style.tap()
                                withAnimation(Style.spring) { previewID = design.id }
                            } label: {
                                VStack(spacing: 6) {
                                    NotebookCoverView(appearance: .design(design.id), title: title)
                                        .aspectRatio(3 / 4, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Style.selection : .clear, lineWidth: 3))
                                        .ambientShadow()
                                    Text(design.name).font(.caption).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
            .background(Color.chrome)
            .navigationTitle("Cover Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .wideSheet()
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Style.tap()
            withAnimation(Style.spring) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? .white : .primary)
                .background(selected ? Style.selection : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paper picker

/// MyScript-style paper cards: each shows the real pattern at small scale.
struct PaperStylePicker: View {
    @Binding var selection: PaperStyle
    var columns = 5

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 14) {
            ForEach(PaperStyle.allCases) { style in
                let selected = selection == style
                Button {
                    Style.tap()
                    withAnimation(Style.spring) { selection = style }
                } label: {
                    VStack(spacing: 6) {
                        PaperSwatch(style: style)
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Style.cardRadius))
                            .overlay(RoundedRectangle(cornerRadius: Style.cardRadius)
                                .strokeBorder(selected ? Style.selection : Color.hairline, lineWidth: selected ? 2.5 : 1))
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white, Style.selection)
                                        .padding(5)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .scaleEffect(selected ? 1.03 : 1)
                            .ambientShadow()
                        Text(style.title)
                            .font(.caption.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Style.selection : .primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(style.title) paper")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// A miniature sheet of paper drawn with the same rules as the editor.
struct PaperSwatch: View {
    let style: PaperStyle

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.paper))
            let spacing = size.width / 8
            let line = Color(uiColor: .paperLine)
            var path = Path()
            switch style {
            case .ruled, .dottedLined:
                var y = size.height * 0.2
                var mid = Path()
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                    mid.move(to: CGPoint(x: 0, y: y + spacing / 2)); mid.addLine(to: CGPoint(x: size.width, y: y + spacing / 2))
                    y += spacing
                }
                context.stroke(path, with: .color(line), lineWidth: 1)
                if style == .dottedLined {
                    context.stroke(mid, with: .color(line.opacity(0.7)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                }
            case .grid:
                stride(from: spacing, to: size.height, by: spacing).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                stride(from: spacing, to: size.width, by: spacing).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                context.stroke(path, with: .color(line), lineWidth: 0.8)
            case .dotted:
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                        context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(line))
                    }
                }
            case .blank:
                break
            }
        }
    }
}
