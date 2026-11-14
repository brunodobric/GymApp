import XCTest

/// Snimke zaslona za App Store. Pokreće ih `scripts/snimke-zaslona.sh` za svaki uređaj i jezik, a slike
/// se izvlače iz rezultata testa u `AppStore/screenshots/`. Aplikacija se pokreće s `-ScreenshotMode`:
/// baza je u memoriji i puni se demo podacima (`DemoDataGenerator`), pa podaci na simulatoru ostaju netaknuti.
///
/// Jezik dolazi iz varijable `SCREENSHOT_LANGUAGE` ("hr" ili "en"); skripta je postavlja kao
/// `TEST_RUNNER_SCREENSHOT_LANGUAGE`, a xcodebuild je prosljeđuje testu bez prefiksa.
final class ScreenshotTests: XCTestCase {

    private struct Texts {
        let home, history, schedules, exercises, statistics: String
        let search: String
        let exercise: String
    }

    private var language: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_LANGUAGE"] == "en" ? "en" : "hr"
    }

    /// Nazivi tabova i vježbe iz String Cataloga i kataloga vježbi.
    private var texts: Texts {
        language == "en"
            ? Texts(
                home: "Home", history: "History", schedules: "Plan", exercises: "Exercises", statistics: "Statistics",
                search: "Bench", exercise: "Barbell Bench Press"
            )
            : Texts(
                home: "Početna", history: "Povijest", schedules: "Plan", exercises: "Vježbe", statistics: "Statistika",
                search: "Potisak", exercise: "Potisak šipkom s klupe"
            )
    }

    @MainActor
    func testAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ScreenshotMode",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "en" ? "en_US" : "hr_HR",
        ]
        app.launch()
        let texts = self.texts

        XCTAssertTrue(tab(texts.home, in: app).waitForExistence(timeout: 20), "Aplikacija se nije otvorila")
        XCTAssertTrue(app.buttons["home.startPlanned"].firstMatch.waitForExistence(timeout: 10), "Nema demo rasporeda")
        snapshot("01-pocetna")

        open(texts.history, in: app)
        snapshot("03-povijest")

        open(texts.statistics, in: app)
        // Grafovi se računaju nakon prikaza.
        sleep(2)
        snapshot("04-statistika")

        open(texts.schedules, in: app)
        snapshot("05-rasporedi")

        open(texts.exercises, in: app)
        snapshot("06-vjezbe")
        openExerciseDetail(texts, in: app)

        // Trening zadnji: otvara se preko cijelog zaslona.
        open(texts.home, in: app)
        app.buttons["home.startPlanned"].firstMatch.tap()
        sleep(2)
        snapshot("02-trening")
    }

    /// Detalj vježbe preko pretrage. Ako pretraga na nekom uređaju ne nađe vježbu, snimka se preskače.
    @MainActor
    private func openExerciseDetail(_ texts: Texts, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap()
        field.typeText(texts.search)
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", texts.exercise)).firstMatch
        guard result.waitForExistence(timeout: 5) else { return }
        result.tap()
        sleep(1)
        snapshot("07-vjezba")
    }

    @MainActor
    private func tab(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[label]
        return inTabBar.exists ? inTabBar : app.buttons[label].firstMatch
    }

    @MainActor
    private func open(_ label: String, in app: XCUIApplication) {
        let button = tab(label, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Nema taba \(label)")
        button.tap()
        sleep(1)
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
