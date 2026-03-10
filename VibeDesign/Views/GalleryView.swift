import SwiftData
import SwiftUI

struct GalleryView: View {
    @Query(sort: \SpaceItem.createdAt, order: .reverse) private var items: [SpaceItem]
    @State private var selectedItem: SpaceItem?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Captures Yet",
                        systemImage: "cube.transparent",
                        description: Text("Take a photo to create your first 3D model.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    GalleryCell(item: item)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Gallery")
            .navigationDestination(for: SpaceItem.self) { item in
                ModelDetailView(item: item)
            }
        }
    }
}

struct GalleryCell: View {
    let item: SpaceItem

    var body: some View {
        AsyncImage(url: URL(string: item.imageUrl)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder(systemName: "exclamationmark.triangle")
            default:
                placeholder(systemName: "photo")
                    .overlay { ProgressView() }
            }
        }
        .frame(minHeight: 150)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) {
            cellOverlay
        }
        .overlay(alignment: .topTrailing) {
            statusBadge
        }
    }

    private var cellOverlay: some View {
        Text(item.name)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                .ultraThinMaterial,
                in: .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 0
                )
            )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case "generating":
            ProgressView()
                .padding(6)
                .background(.ultraThinMaterial, in: .circle)
        case "failed":
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .padding(6)
                .background(.ultraThinMaterial, in: .circle)
        default:
            EmptyView()
        }
    }

    private func placeholder(systemName: String) -> some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: systemName)
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }
}
