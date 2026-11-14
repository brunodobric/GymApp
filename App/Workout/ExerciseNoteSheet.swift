import SwiftUI

/// Uređivanje trajne bilješke vježbe (postavka sprave, hvat, širina stava), `ExerciseNotes`.
/// Bilješka se vidi u kartici vježbe u svakom treningu. Prazan tekst je briše.
struct ExerciseNoteSheet: View {
    let exerciseName: String
    let initialText: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Npr. sjedalo na 4, hvat malo širi", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isFocused)
                } footer: {
                    Text("Bilješka se prikazuje uz vježbu u svakom treningu.")
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Odustani") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spremi") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
            .onAppear {
                text = initialText
                isFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}
