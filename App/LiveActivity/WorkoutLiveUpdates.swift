import ActivityKit
import Connectivity
import Foundation
import Models
import OSLog
import SwiftData
import Training
import Units

/// Sve što aktivni trening pokazuje izvan aplikacije (specifikacija, odjeljak 6): Live Activity na zaključanom
/// zaslonu i u Dynamic Islandu te obavijest o kraju odmora.
///
/// Stanje se uvijek slaže iznova iz baze (aktivni trening), pa je svejedno odakle je promjena došla:
/// s ekrana treninga, sa sata, iz gumba u Live Activityju ili iz povratka u aplikaciju.
@MainActor
final class WorkoutLiveUpdates {
    static let shared = WorkoutLiveUpdates()

    private let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "LiveActivity")
    /// Osvježavanja idu jedno za drugim, da dva brza poziva ne pokrenu dvije Live Activityje.
    private var lastRefresh: Task<Void, Never>?
    /// Odgođeno osvježavanje: niz brzih izmjena (tipkanje u polje serije) daje jedno ažuriranje Live Activityja,
    /// jer ActivityKit ograničava broj ažuriranja.
    private var pendingRefresh: Task<Void, Never>?
    /// Prethodne vrijednosti po vježbi za trening u tijeku. Završeni treninzi se tijekom treninga ne mijenjaju,
    /// pa se povijest vježbe ne čita iznova pri svakom osvježavanju.
    private var previousSessionID: UUID?
    private var previousByExercise: [String: [SetValues]] = [:]

    /// Odgoda osvježavanja nakon zadnje izmjene.
    private static let debounce: Duration = .milliseconds(400)

    private init() {}

    private var context: ModelContext { AppServices.container.mainContext }

    /// Osvježava Live Activity i obavijest prema aktivnom treningu, bez čekanja. Više poziva u kratkom
    /// razmaku daje jedno osvježavanje.
    func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            _ = self?.enqueue()
        }
    }

    /// Kao `refresh()`, ali odmah i čeka da Live Activity bude ažurirana (za radnje koje sustav izvodi u pozadini).
    func refreshAndWait() async {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        await enqueue().value
    }

    private func enqueue() -> Task<Void, Never> {
        let previous = lastRefresh
        let task = Task { [weak self] in
            await previous?.value
            await self?.apply()
        }
        lastRefresh = task
        return task
    }

    private func apply() async {
        let queries = GymQueries(context: context)
        let session = (try? queries.activeSession()).flatMap { $0.state == .active ? $0 : nil }
        // Postavke se čitaju samo uz trening: `settings()` bi ih inače stvorio još prije onboardinga.
        let settings = session != nil ? try? queries.settings() : nil
        let status = session.map { WorkoutEngine(context: context).liveStatus(of: $0) }

        scheduleRestNotification(session: session, status: status, settings: settings)
        if let session, let status {
            await show(session: session, status: status, unit: settings?.weightUnit ?? .kilograms)
        } else {
            await endAll()
        }
    }

    // MARK: Obavijest o kraju odmora

    private func scheduleRestNotification(session: Session?, status: LiveWorkoutStatus?, settings: UserSettings?) {
        let fireDate = RestNotificationPolicy.fireDate(
            restEndsAt: status?.rest?.endsAt,
            controllingDevice: session?.controllingDevice ?? .phone,
            notificationsEnabled: settings?.restNotificationEnabled ?? true,
            isSessionActive: session != nil,
            watchAlertsRest: session?.healthRecordedByWatch ?? false,
            now: Date()
        )
        RestNotifications.schedule(
            at: fireDate,
            body: Self.notificationBody(for: status),
            soundEnabled: settings?.restEndSoundEnabled ?? true
        )
    }

    private static func notificationBody(for status: LiveWorkoutStatus?) -> String {
        guard let status, let name = status.currentExerciseName else {
            return String(localized: "Vrijeme za sljedeću seriju.")
        }
        return String(localized: "Sljedeće: \(name), serija \(status.setNumber) od \(status.setCount).")
    }

    // MARK: Live Activity

    private func show(session: Session, status: LiveWorkoutStatus, unit: WeightUnit) async {
        let sessionID = session.id.uuidString
        let state = Self.contentState(session: session, status: status, next: nextSetDetails(in: session, unit: unit))
        let now = Date()
        // Kad odmor istekne, sadržaj zastari i widget umjesto odbrojavanja piše da je odmor gotov.
        let staleDate = status.rest.flatMap { $0.endsAt > now ? $0.endsAt : nil }
        let content = ActivityContent(state: state, staleDate: staleDate)

        var current: Activity<RestTimerActivityAttributes>?
        for activity in Activity<RestTimerActivityAttributes>.activities {
            if activity.attributes.sessionID == sessionID, current == nil,
               [.active, .stale].contains(activity.activityState) {
                current = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        if let current {
            // Bez `AlertConfiguration`: ažuriranje je tiho, bez zvuka i bannera.
            if current.content.state != state || current.content.staleDate != staleDate {
                await current.update(content)
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let attributes = RestTimerActivityAttributes(sessionID: sessionID, workoutName: session.name)
            _ = try Activity<RestTimerActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            // Live Activity se može pokrenuti samo dok je aplikacija otvorena (npr. trening započet na satu
            // dok je iPhone zaključan). Pokreće se pri sljedećem povratku u aplikaciju.
            logger.info("Live Activity nije pokrenuta: \(error.localizedDescription)")
        }
    }

    /// Trening je završen ili odbačen: Live Activity se gasi odmah.
    private func endAll() async {
        for activity in Activity<RestTimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Vrijednosti serije koju gumb potvrđuje i ista serija u prethodnom treningu, formatirane za widget
    /// (koji ne ovisi o GymKitu).
    private func nextSetDetails(in session: Session, unit: WeightUnit) -> NextSetDetails {
        guard let set = WorkoutEngine(context: context).nextSet(in: session), let exercise = set.exercise else {
            return NextSetDetails(values: [], previousText: nil)
        }
        let values = LiveSetEditor.values(of: set, inputType: exercise.inputType, unit: unit).map(\.activityValue)
        let previous = previousValues(of: exercise, in: session)
        let previousText = LiveSetEditor.previousText(of: set, inputType: exercise.inputType, previous: previous, unit: unit)
        return NextSetDetails(values: values, previousText: previousText)
    }

    private func previousValues(of exercise: SessionExercise, in session: Session) -> [SetValues] {
        if previousSessionID != session.id {
            previousSessionID = session.id
            previousByExercise = [:]
        }
        let key = exercise.exercise.key
        if let cached = previousByExercise[key] { return cached }
        let values = (try? GymQueries(context: context).previousSetValues(of: exercise.exercise)) ?? []
        previousByExercise[key] = values
        return values
    }

    private struct NextSetDetails {
        var values: [RestTimerActivityAttributes.SetValue]
        var previousText: String?
    }

    private static func contentState(
        session: Session,
        status: LiveWorkoutStatus,
        next: NextSetDetails
    ) -> RestTimerActivityAttributes.ContentState {
        RestTimerActivityAttributes.ContentState(
            exerciseName: status.currentExerciseName,
            nextExerciseName: status.nextExerciseName,
            setNumber: status.setNumber,
            setCount: status.setCount,
            completedSets: status.completedSets,
            totalSets: status.totalSets,
            nextSetID: status.nextSetID?.uuidString,
            setValues: next.values,
            previousText: next.previousText,
            canConfirm: status.canConfirmNextSet,
            restStartedAt: status.rest?.startedAt,
            restEndsAt: status.rest?.endsAt,
            workoutStartedAt: session.startedAt,
            isLedByWatch: session.controllingDevice == .watch
        )
    }
}

extension LiveSetValue {
    /// Vrijednost za Live Activity i karticu treninga na Početnoj (widget ne ovisi o GymKitu).
    var activityValue: RestTimerActivityAttributes.SetValue {
        RestTimerActivityAttributes.SetValue(
            field: field.rawValue,
            text: text,
            unitSymbol: unitSymbol,
            canDecrease: canDecrease,
            canIncrease: canIncrease
        )
    }
}
