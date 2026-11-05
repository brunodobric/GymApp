import Testing
@testable import Catalog

@Suite("Tekst licence")
struct LicenseTextTests {

    @Test("Prijelomi unutar odlomka se spajaju, a odlomci i stavke ostaju odvojeni")
    func reflow() {
        let raw = "MIT License\n\nPermission is hereby granted,\nfree of charge.\n- first item\n- second item\n"
        let expected = "MIT License\n\nPermission is hereby granted, free of charge.\n\n- first item\n\n- second item"
        #expect(LicenseText.reflowed(raw) == expected)
    }

    @Test("Prazan tekst daje prazan rezultat")
    func empty() {
        #expect(LicenseText.reflowed("").isEmpty)
    }
}
