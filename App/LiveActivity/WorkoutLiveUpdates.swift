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

    private init() {}

    private var context: ModelContext { AppServices.container.mainContext }

    /// Osvježava Live Activity i obavijest prema aktivnom treningu, bez čekanja.
    func refresh() {
        _ = enqueue()
    }

    /// Kao `refresh()`, ali čeka da Live Activity bude ažurirana (za radnje koje sustav izvodi u pozadini).
    func refreshAndWait() async {
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
            notificationsEnabled: settings?.notificationsEnabled ?? true,
            isSessionActive: session != nil,
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
        let values = LiveSetEditor.values(of: set, inputType: exercise.inputType, unit: unit).map { value in
            RestTimerActivityAttributes.SetValue(
                field: value.field.rawValue,
                text: value.text,
                unitSymbol: value.unitSymbol,
                canDecrease: value.canDecrease,
                canIncrease: value.canIncrease
            )
        }
        let last = try? GymQueries(context: context).lastPerformance(of: exercise.exercise)
        let previous = last?.orderedSets.filter(\.isCompleted).map(\.values) ?? []
        let previousText = LiveSetEditor.previousText(of: set, inputType: exercise.inputType, previous: previous, unit: unit)
        return NextSetDetails(values: values, previousText: previousText)
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
