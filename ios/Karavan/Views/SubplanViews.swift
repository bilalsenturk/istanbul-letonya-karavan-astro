import MapKit
import SwiftUI

struct AddSubplanFlowView: View {
    let daySlug: String
    @State private var place: RouteDraftStop?

    var body: some View {
        if let place {
            SubplanEditorView(daySlug: daySlug, place: place)
        } else {
            PlacePickerView(
                title: "Alt plan yeri",
                allowsCurrentLocation: false,
                transportMode: .automobile,
                dismissAfterSelection: false
            ) { place = $0 }
        }
    }
}

struct SubplanDetailView: View {
    let daySlug: String
    let subplan: DaySubplan
    @EnvironmentObject private var plan: TripPlanStore
    @EnvironmentObject private var role: RoleStore
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    private var current: DaySubplan {
        plan.edits.days[daySlug]?.subplans?.first(where: { $0.id == subplan.id }) ?? subplan
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Map {
                        Marker(current.placeName, coordinate: coordinate)
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(SubplanCompactRow.timeText(current.startMinute))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.c2)
                        Text(current.title)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(current.placeName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }

                    LabeledContent("Süre", value: "\(current.durationMinutes) dakika")
                        .foregroundStyle(Theme.text)
                        .padding(12)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))

                    if let note = current.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.dim)
                    }

                    Button {
                        NavApp.openAppleMaps(toCoordinate: coordinate, name: current.placeName)
                    } label: {
                        Label(role.isDriver ? "Buraya git" : "Yalnız sürücü başlatabilir", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.c2)
                    .disabled(!role.isDriver)

                    Button("Alt planı sil", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Düzenle") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            SubplanEditorView(
                daySlug: daySlug,
                place: RouteDraftStop(
                    id: current.id,
                    name: current.placeName,
                    lat: current.latitude,
                    lng: current.longitude
                ),
                existing: current
            )
        }
        .alert("Alt plan silinsin mi?", isPresented: $confirmDelete) {
            Button("Sil", role: .destructive) {
                plan.removeSubplan(id: current.id, slug: daySlug)
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: current.latitude, longitude: current.longitude)
    }
}

struct SubplanEditorView: View {
    let daySlug: String
    let place: RouteDraftStop
    let existing: DaySubplan?

    @EnvironmentObject private var plan: TripPlanStore
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var startMinute: Int
    @State private var durationMinutes: Int
    @State private var note: String
    @State private var inboundMinutes: Int?
    @State private var outboundMinutes: Int?
    @State private var previousEndMinute: Int?
    @State private var nextLimitMinute: Int?
    @State private var nextIsSubplan = false
    @State private var isLoading = true
    @State private var routeError: String?

    init(daySlug: String, place: RouteDraftStop, existing: DaySubplan? = nil) {
        self.daySlug = daySlug
        self.place = place
        self.existing = existing
        _title = State(initialValue: existing?.title ?? place.name)
        _startMinute = State(initialValue: existing?.startMinute ?? 12 * 60)
        _durationMinutes = State(initialValue: existing?.durationMinutes ?? 60)
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alt plan") {
                    TextField("Başlık", text: $title)
                    LabeledContent("Yer", value: place.name)
                    DatePicker("Başlangıç", selection: startTime, displayedComponents: .hourAndMinute)
                    Stepper("Süre · \(durationMinutes) dk", value: $durationMinutes, in: 15 ... 360, step: 15)
                    TextField("Not", text: $note, axis: .vertical)
                        .lineLimit(2 ... 4)
                }

                Section("Otomatik rota") {
                    if isLoading {
                        HStack { ProgressView(); Text("Apple Maps süresi hesaplanıyor") }
                    } else if let inboundMinutes {
                        LabeledContent("Önceki plandan", value: durationText(inboundMinutes))
                        if let outboundMinutes {
                            LabeledContent(nextIsSubplan ? "Sonraki alt plana" : "Sonraki ana hedefe", value: durationText(outboundMinutes))
                        }
                    }
                    if let routeError {
                        Text(routeError).foregroundStyle(Theme.warn)
                    }
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warn)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(existing == nil ? "Alt plan ekle" : "Alt planı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .task { await calculateSchedule() }
    }

    private var effectiveDay: EffectiveDay? {
        plan.day(store.trip, slug: daySlug)
    }

    private var startTime: Binding<Date> {
        Binding {
            guard let day = effectiveDay else { return Date() }
            return TripPlanner.routeCalendar.date(
                byAdding: .minute,
                value: startMinute,
                to: TripPlanner.routeCalendar.startOfDay(for: day.date)
            ) ?? day.date
        } set: { value in
            let cal = TripPlanner.routeCalendar
            startMinute = cal.component(.hour, from: value) * 60 + cal.component(.minute, from: value)
        }
    }

    private var scheduleEntry: PlanScheduleEntry? {
        guard let previousEndMinute, let inboundMinutes else { return nil }
        return PlanScheduleEntry(
            id: existing?.id ?? place.id,
            requestedStartMinute: startMinute,
            previousEndMinute: previousEndMinute,
            travelMinutes: inboundMinutes,
            durationMinutes: durationMinutes
        )
    }

    private var validationMessage: String? {
        guard !isLoading else { return nil }
        if let entry = scheduleEntry,
           let conflict = PlanScheduleValidator.conflict(for: entry) {
            return "Bu saate yetişilemez. En erken \(SubplanCompactRow.timeText(conflict.earliestStartMinute))."
        }
        if let nextLimitMinute {
            let travel = nextIsSubplan ? (outboundMinutes ?? 0) : 0
            if !PlanScheduleValidator.fitsBeforeNextDeparture(
                finishMinute: startMinute + durationMinutes,
                travelMinutesToNext: travel,
                nextDepartureMinute: nextLimitMinute
            ) {
                let latest = max(0, nextLimitMinute - travel - durationMinutes)
                return "Sonraki plana yetişmek için en geç \(SubplanCompactRow.timeText(latest)) başlangıç gerekir."
            }
        }
        return routeError
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
            && validationMessage == nil
    }

    private func calculateSchedule() async {
        guard let day = effectiveDay, let trip = store.trip else {
            routeError = "Gün planı yüklenemedi."
            isLoading = false
            return
        }
        isLoading = true
        routeError = nil

        let others = day.subplans
            .filter { $0.id != existing?.id }
            .sorted { $0.startMinute < $1.startMinute }
        let neighbors = PlanScheduleValidator.neighbors(
            for: startMinute,
            excludingID: existing?.id,
            in: day.subplans
        )
        let previous = others.first { $0.id == neighbors.previousID }
        let next = others.first { $0.id == neighbors.nextID }
        let target = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)

        if let previous {
            previousEndMinute = previous.startMinute + previous.durationMinutes
            inboundMinutes = await routeMinutes(
                from: CLLocationCoordinate2D(latitude: previous.latitude, longitude: previous.longitude),
                to: target
            )
        } else if let destination = destinationCoordinate(day: day, trip: trip) {
            let departureMinute = minuteOfDay(day.departTime)
            let mainMinutes: Int
            if day.isRestDay {
                mainMinutes = 0
            } else if let origin = trip.stop(matching: day.origin)?.coordinate {
                mainMinutes = await routeMinutes(from: origin, to: destination) ?? 0
            } else {
                mainMinutes = 0
            }
            previousEndMinute = departureMinute + mainMinutes
            inboundMinutes = await routeMinutes(from: destination, to: target)
        }

        if let next {
            nextIsSubplan = true
            nextLimitMinute = next.startMinute
            outboundMinutes = await routeMinutes(
                from: target,
                to: CLLocationCoordinate2D(latitude: next.latitude, longitude: next.longitude)
            )
        } else if let nextDay = nextDay(after: day) {
            nextIsSubplan = false
            let dayDistance = TripPlanner.routeCalendar.dateComponents(
                [.day],
                from: TripPlanner.routeCalendar.startOfDay(for: day.date),
                to: TripPlanner.routeCalendar.startOfDay(for: nextDay.date)
            ).day ?? 1
            nextLimitMinute = dayDistance * 24 * 60 + minuteOfDay(nextDay.departTime)
            if let nextDestination = destinationCoordinate(day: nextDay, trip: trip) {
                outboundMinutes = await routeMinutes(from: target, to: nextDestination)
            }
        }

        if inboundMinutes == nil || previousEndMinute == nil {
            routeError = "Rota süresi hesaplanamadı; plan kaydedilmedi."
        } else if existing == nil, let entry = scheduleEntry, startMinute < entry.earliestStartMinute {
            startMinute = roundedQuarter(entry.earliestStartMinute)
        }
        isLoading = false
    }

    private func destinationCoordinate(day: EffectiveDay, trip: TripData) -> CLLocationCoordinate2D? {
        if let target = day.arrivalTarget, target.hasValidCoordinate {
            return CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
        }
        return trip.stop(matching: day.destination)?.coordinate
    }

    private func nextDay(after day: EffectiveDay) -> EffectiveDay? {
        let values = plan.days(store.trip)
        guard let index = values.firstIndex(where: { $0.id == day.id }), values.indices.contains(index + 1) else { return nil }
        return values[index + 1]
    }

    private func routeMinutes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        return max(1, Int(ceil(route.expectedTravelTime / 60)))
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let cal = TripPlanner.routeCalendar
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private func roundedQuarter(_ minute: Int) -> Int {
        min(23 * 60 + 45, ((minute + 14) / 15) * 15)
    }

    private func durationText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) dk" : "\(minutes / 60) sa \(minutes % 60) dk"
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.upsertSubplan(
            DaySubplan(
                id: existing?.id ?? UUID().uuidString,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                placeName: place.name,
                latitude: place.lat,
                longitude: place.lng,
                startMinute: startMinute,
                durationMinutes: durationMinutes,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            ),
            slug: daySlug
        )
        dismiss()
    }
}
