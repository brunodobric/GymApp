import SwiftUI
import Units

/// Polje za težinu ili ponavljanja koje umjesto tipkovnice otvara kotačić.
/// Dodir na veliki broj iznad kotačića otvara tipkovnicu za vrijednost koje nema na kotačiću.
/// Polje radi s tekstom kao i obično polje, pa postojeća logika spremanja (`apply`, `sync`) ostaje ista.
struct WheelInputField: View {
    let title: LocalizedStringKey
    /// Kratka oznaka jedinice ("kg", "×"), u praznom polju i uz broj iznad kotačića.
    let hint: String
    @Binding var text: String
    /// Vrijednosti kotačića za trenutnu vrijednost polja (ona mora biti na popisu).
    let options: (Double?) -> [Double]
    /// Vrijednost na koju se kotačić postavi kad je polje prazno.
    let fallback: Double
    let format: (Double) -> String
    let parse: (String) -> Double?
    var keyboard: UIKeyboardType = .decimalPad
    /// Dodatna radnja na dugi pritisak (kalkulator ploča uz težinu).
    var longPress: (label: LocalizedStringKey, action: () -> Void)?

    @State private var isPresented = false

    var body: some View {
        Text(verbatim: text.isEmpty ? hint : text)
            .foregroundStyle(text.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .setFieldFrame()
            .contentShape(.rect)
            .onTapGesture { isPresented = true }
            .onLongPressGesture(minimumDuration: 0.6) { longPress?.action() }
            .accessibilityElement()
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(verbatim: text))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isPresented = true }
            .accessibilityActions {
                if let longPress {
                    Button(longPress.label, action: longPress.action)
                }
            }
            .popover(isPresented: $isPresented) {
                let current = parse(text)
                WheelInputPanel(
                    title: title, hint: hint, text: $text, options: options(current),
                    start: current ?? fallback, keyboard: keyboard, format: format
                )
                // I na iPhoneu ostaje oblačić uz polje, da se vidi koja se serija mijenja.
                .presentationCompactAdaptation(.popover)
            }
    }
}

/// Sadržaj oblačića: naslov, broj koji se dodirom pretvara u polje za tipkovnicu i kotačić.
private struct WheelInputPanel: View {
    let title: LocalizedStringKey
    let hint: String
    @Binding var text: String
    let options: [Double]
    let keyboard: UIKeyboardType
    let format: (Double) -> String

    @State private var selection: Double
    @State private var isTyping = false
    /// Tekst s tipkovnice. Počinje prazan da se novi broj ne lijepi na stari.
    @State private var typed = ""
    /// Vrijednost prije tipkanja, vraća se ako korisnik obriše sve što je upisao.
    @State private var textBeforeTyping = ""
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 260
    @Environment(\.dismiss) private var dismiss

    init(
        title: LocalizedStringKey, hint: String, text: Binding<String>, options: [Double], start: Double,
        keyboard: UIKeyboardType, format: @escaping (Double) -> String
    ) {
        self.title = title
        self.hint = hint
        _text = text
        self.options = options
        self.keyboard = keyboard
        self.format = format
        _selection = State(initialValue: WheelOptions.nearest(to: start, in: options) ?? start)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Gotovo") { dismiss() }
                    .bold()
            }
            if isTyping {
                TextField(text: $typed, prompt: Text(verbatim: textBeforeTyping.isEmpty ? hint : textBeforeTyping)) {
                    Text(title)
                }
                .keyboardType(keyboard)
                .font(.largeTitle.monospacedDigit().bold())
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .padding(.vertical, 8)
                .background(.quaternary, in: .rect(cornerRadius: 10))
                .onAppear { isFocused = true }
                .onChange(of: typed) { _, new in
                    text = new.trimmingCharacters(in: .whitespaces).isEmpty ? textBeforeTyping : new
                }
            } else {
                Button(action: startTyping) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: text.isEmpty ? format(selection) : text)
                            .font(.largeTitle.monospacedDigit().bold())
                        Text(verbatim: hint)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(verbatim: text))
                .accessibilityHint(Text("Upiši broj tipkovnicom"))

                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { value in
                        Text(verbatim: format(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 180)

                Text("Dodirni broj za upis tipkovnicom")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(width: width)
        // Prazno polje odmah dobiva vrijednost s kotačića, pa "Gotovo" bez okretanja prihvaća ono što se vidi.
        .onAppear { if text.isEmpty { text = format(selection) } }
        .onChange(of: selection) { _, new in
            if !isTyping { text = format(new) }
        }
    }

    private func startTyping() {
        textBeforeTyping = text
        typed = ""
        isTyping = true
    }
}

// MARK: Težina i ponavljanja

extension WheelInputField {
    /// Polje za težinu u jedinici korisnika: koraci od 2,5 kg ili 5 lbs.
    static func weight(
        _ title: LocalizedStringKey, hint: String, text: Binding<String>, unit: WeightUnit,
        fallback: Double, longPress: (label: LocalizedStringKey, action: () -> Void)? = nil
    ) -> WheelInputField {
        WheelInputField(
            title: title, hint: hint, text: text,
            options: { WheelOptions.weights(for: unit, including: $0) },
            fallback: fallback,
            format: { NumberInput.format($0) },
            parse: { NumberInput.parse($0) },
            keyboard: .decimalPad,
            longPress: longPress
        )
    }

    /// Polje za ponavljanja: od 1 do 50.
    static func reps(_ title: LocalizedStringKey, hint: String, text: Binding<String>, fallback: Int) -> WheelInputField {
        WheelInputField(
            title: title, hint: hint, text: text,
            options: { WheelOptions.reps(including: $0.map { Int($0) }).map(Double.init) },
            fallback: Double(fallback),
            format: { String(Int($0)) },
            parse: { Int($0.trimmingCharacters(in: .whitespaces)).map(Double.init) },
            keyboard: .numberPad
        )
    }
}
