import SwiftUI

extension View {
    /// Upozorenje o grešci: prikazuje se dok tekst postoji, a gumb U redu ga briše.
    /// Zajedničko svim ekranima koji javljaju neuspjelo spremanje ili brisanje.
    func errorAlert(_ text: Binding<String?>) -> some View {
        alert("Greška", isPresented: Binding(
            get: { text.wrappedValue != nil },
            set: { if !$0 { text.wrappedValue = nil } }
        )) {
            Button("U redu") {}
        } message: {
            Text(text.wrappedValue ?? "")
        }
    }
}
