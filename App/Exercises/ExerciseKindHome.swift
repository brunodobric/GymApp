import Catalog
import Models
import SwiftUI

/// Početna kataloga: kartice vrsta (2 × 2 na iPhoneu) i poveznice na sve i vlastite vježbe.
struct ExerciseKindHome: View {
    let customExercises: [CustomExercise]

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let customSummaries = customExercises.map(\.summary)
        let counts = ExerciseSearch.countsByKind(catalogStore.summaries + customSummaries)
        ScrollView {
            VStack(spacing: 20) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ExerciseKind.allCases, id: \.self) { kind in
                        NavigationLink(value: ExerciseListRoute.kind(kind)) {
                            ExerciseKindCard(
                                kind: kind,
                                count: counts[kind, default: 0],
                                thumbnails: catalogStore.featuredThumbnails(kind)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                links(
                    allCount: counts.values.reduce(0, +),
                    customCount: customSummaries.filter { !$0.isArchived }.count
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// Dva stupca na iPhoneu, više na iPadu, jedan stupac kod veličina teksta za pristupačnost.
    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else if sizeClass == .regular {
            [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)]
        } else {
            [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), alignment: .top)]
        }
    }

    private func links(allCount: Int, customCount: Int) -> some View {
        VStack(spacing: 0) {
            LinkRow(title: "Sve vježbe", count: allCount, route: .all)
            Divider().padding(.leading)
            LinkRow(title: "Moje vježbe", count: customCount, route: .custom)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.card))
    }
}

/// Redak poveznice ispod kartica, izgleda kao redak sistemskog popisa.
private struct LinkRow: View {
    let title: LocalizedStringResource
    let count: Int
    let route: ExerciseListRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack {
                Text(title)
                Spacer()
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kartica vrste: četiri sličice u kvadratu, naziv i broj vježbi.
private struct ExerciseKindCard: View {
    let kind: ExerciseKind
    let count: Int
    let thumbnails: [ExerciseThumbnail.Source]

    private let padding: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mosaic
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.headline)
                Text("\(count) vježbi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.card))
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: CornerRadius.card))
        .hoverEffect()
        .accessibilityElement(children: .combine)
    }

    /// 2 × 2 sličice. Bez MoveKit dodatka (nema sličica) stoji simbol vrste.
    @ViewBuilder
    private var mosaic: some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.card - padding)
        if thumbnails.count == 4 {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    tile(thumbnails[0])
                    tile(thumbnails[1])
                }
                GridRow {
                    tile(thumbnails[2])
                    tile(thumbnails[3])
                }
            }
            .clipShape(shape)
        } else {
            Color(.tertiarySystemFill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: kind.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
                .clipShape(shape)
                .accessibilityHidden(true)
        }
    }

    private func tile(_ source: ExerciseThumbnail.Source) -> some View {
        ExerciseThumbnail(source: source, cornerRadius: 0, aspectRatio: 1, zoom: 1.4)
    }
}
