import Testing
@testable import Models

@Suite("Trajne bilješke vježbi")
struct ExerciseNotesTests {

    @Test("Bilješka se sprema, briše praznim tekstom i daje isti JSON kao Android")
    func roundTrip() {
        var notes = ExerciseNotes()
        notes.setNote("  Sjedalo 4, hvat širi  ", for: "c:bench")
        notes.setNote("Sprava 3/5", for: "c:a-row")
        #expect(notes.note(for: "c:bench") == "Sjedalo 4, hvat širi")
        #expect(notes.raw == #"{"c:a-row":"Sprava 3/5","c:bench":"Sjedalo 4, hvat širi"}"#)

        var decoded = ExerciseNotes(raw: notes.raw)
        #expect(decoded == notes)
        decoded.setNote("   ", for: "c:bench")
        decoded.setNote("", for: "c:a-row")
        #expect(decoded.note(for: "c:bench") == nil)
        #expect(decoded.raw.isEmpty)
    }

    @Test("Neispravan zapis daje prazne bilješke")
    func invalidRaw() {
        #expect(ExerciseNotes(raw: "nije json").notes.isEmpty)
        #expect(ExerciseNotes(raw: "").note(for: "c:bench") == nil)
    }
}
