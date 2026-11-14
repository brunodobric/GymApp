import Models
import SwiftData
import SwiftUI

/// Trajna bilješka vježbe na stranici vježbe (`ExerciseNotes`): prikaz i uređivanje.
/// Ista bilješka se vidi u kartici vježbe u treningu.
struct ExerciseNoteSection: View {
    let ref: ExerciseRef

    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @State private var isEditing = false

    private var note: String? { UserSettings.preferred(in: settingsList)?.exerciseNotes.note(for: ref.key) }

    var body: some View {
        Section("Bilješka") {
            if let note {
                Text(note)
                Button("Uredi bilješku", systemImage: "pencil") { isEditing = true }
            } else {
                Button("Dodaj bilješku", systemImage: "note.text") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            ExerciseNoteSheet(exerciseName: ref.name, initialText: note ?? "") { text in
                guard let settings = try? GymQueries(context: context).settings() else { return }
                var notes = settings.exerciseNotes
                notes.setNote(text, for: ref.key)
                settings.exerciseNotes = notes
                try? context.save()
            }
        }
    }
}
