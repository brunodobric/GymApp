import XCTest

/// Ploče Katalog i Treninzi na iPhoneu: odabir redaka, gumb Dodaj (n) i Zatvori.
///
/// Pokreće se s demo podacima (`-ScreenshotMode`), pa podaci na simulatoru ostaju netaknuti.
final class PlanningPanelTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ScreenshotMode", "-AppleLanguages", "(hr)", "-AppleLocale", "hr_HR"]
        app.launch()
        let tab = app.tabBars.buttons["Rasporedi"].exists ? app.tabBars.buttons["Rasporedi"] : app.buttons["Rasporedi"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Nema taba Rasporedi")
        tab.tap()
        return app
    }

    @MainActor
    private func create(_ item: String, in app: XCUIApplication) {
        let menu = app.navigationBars.buttons["Dodaj"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Nema izbornika Dodaj")
        menu.tap()
        let button = app.buttons[item].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Nema stavke \(item)")
        button.tap()
    }

    /// Odabere prva dva retka u ploči, provjeri Dodaj (2) prije i nakon scrollanja i doda ih.
    @MainActor
    private func selectAndAdd(in app: XCUIApplication, openButton: String) {
        let open = app.buttons[openButton].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Nema gumba \(openButton)")
        // Zatvorena ploča ne smije ostaviti svoje gumbe u navigacijskoj traci uređivača.
        XCTAssertFalse(app.buttons["planningPanel.close"].exists, "Gumbi ploče vide se i kad je ploča zatvorena")
        open.tap()

        let add = app.buttons["planningPanel.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Ploča se nije otvorila")
        attach(app, "ploca-otvorena")
        XCTAssertFalse(add.isEnabled, "Dodaj je omogućen bez odabira")

        // Retci ploče su gumbi s kružićem; prvi i drugi u listu.
        let rows = app.collectionViews["planningPanel.list"].buttons
        XCTAssertTrue(rows.element(boundBy: 1).waitForExistence(timeout: 5), "Ploča nema dva retka")
        rows.element(boundBy: 0).tap()
        rows.element(boundBy: 1).tap()
        attach(app, "nakon-odabira")
        print("DIJAGNOSTIKA nakon odabira:\n\(app.debugDescription)")
        XCTAssertTrue(waitUntil { add.isEnabled }, "Dodaj nije omogućen nakon odabira dva retka")
        XCTAssertEqual(add.label, "Dodaj (2)")

        app.collectionViews["planningPanel.list"].swipeUp()
        app.collectionViews["planningPanel.list"].swipeDown()
        XCTAssertTrue(add.isEnabled, "Dodaj nije omogućen nakon scrollanja")

        add.tap()
        XCTAssertTrue(waitUntil { !add.exists }, "Ploča se nije zatvorila nakon Dodaj")
        XCTAssertFalse(app.buttons["planningPanel.close"].exists, "Gumbi ploče ostali su nakon zatvaranja")
    }

    @MainActor
    private func openAndClose(in app: XCUIApplication, openButton: String) {
        app.buttons[openButton].firstMatch.tap()
        let close = app.buttons["planningPanel.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Ploča se nije otvorila")
        close.tap()
        XCTAssertTrue(waitUntil { !close.exists }, "Ploča se nije zatvorila na Zatvori")
    }

    @MainActor
    func testCatalogPanel() {
        let app = launch()
        create("Novi trening", in: app)
        selectAndAdd(in: app, openButton: "Dodaj vježbe")
        openAndClose(in: app, openButton: "Dodaj vježbe")
    }

    @MainActor
    func testTemplatePanel() {
        let app = launch()
        create("Novi raspored", in: app)
        selectAndAdd(in: app, openButton: "Odaberi više treninga")
        openAndClose(in: app, openButton: "Odaberi više treninga")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
