import Models
import SwiftUI

/// Izbor jednog od nekoliko odgovora kao kartice u dva stupca. Ponovni dodir poništava odabir.
struct ChoiceGrid<Item: Hashable, Content: View>: View {
    let items: [Item]
    @Binding var selection: Item?
    let content: (Item) -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ items: [Item], selection: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        _selection = selection
        self.content = content
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    selection = isSelected ? nil : item
                } label: {
                    content(item)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .background(
                            isSelected ? AnyShapeStyle(TintShapeStyle().opacity(0.12)) : AnyShapeStyle(Color(.quaternarySystemFill)),
                            in: .rect(cornerRadius: CornerRadius.inner)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: CornerRadius.inner)
                                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Dani tjedno kao krugovi od 1 do 7. Ponovni dodir poništava odabir.
struct DaysPicker: View {
    @Binding var days: Int?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(OnboardingAnswers.daysPerWeekRange), id: \.self) { day in
                let isSelected = days == day
                Button {
                    days = isSelected ? nil : day
                } label: {
                    Text(day, format: .number)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.quaternarySystemFill)), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("\(day) dana tjedno"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
