import MapKit
import SwiftUI

struct StopEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stop: RouteDraftStop
    @State private var hasArrival: Bool
    @State private var showTargetPicker = false
    @State private var showTargetEditor = false
    let routeId: String
    let onSave: (RouteDraftStop) -> Void

    init(stop: RouteDraftStop, routeId: String = "local", onSave: @escaping (RouteDraftStop) -> Void) {
        _stop = State(initialValue: stop)
        _hasArrival = State(initialValue: stop.arrivalAt != nil)
        self.routeId = routeId
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Durak") {
                    TextField("Ad", text: $stop.name)
                    TextField("Not", text: $stop.note, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Plan") {
                    Toggle("Varış tarihi", isOn: $hasArrival)
                    if hasArrival {
                        DatePicker("Varış", selection: Binding(
                            get: { stop.arrivalAt ?? Date() },
                            set: { stop.arrivalAt = $0 }
                        ))
                    }
                    TextField("Konaklama", text: $stop.accommodation)
                    TextField("Bağlantı", text: $stop.link)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                Section("Kesin varış noktası") {
                    if let target = stop.arrivalTarget {
                        LabeledContent("Yer", value: target.name)
                        Text(target.formattedAddress).font(.footnote).foregroundStyle(.secondary)
                        Button { showTargetEditor = true } label: {
                            Label("İletişim ve rezervasyon", systemImage: "message.badge.fill")
                        }
                        Button { showTargetPicker = true } label: {
                            Label("Varış yerini değiştir", systemImage: "map.fill")
                        }
                    } else {
                        Text("Bu şehir yalnız etap bilgisidir. Gerçek kamp, otel veya adresi seçin.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button { showTargetPicker = true } label: {
                            Label("Varış yerini seç", systemImage: "map.fill")
                        }
                    }
                }
                Section {
                    LabeledContent("Etap şehri", value: stop.name)
                    LabeledContent("Şehir koordinatı", value: String(format: "%.4f, %.4f", stop.lat, stop.lng))
                }
            }
            .navigationTitle("Durak ayrıntısı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        if !hasArrival { stop.arrivalAt = nil }
                        onSave(stop)
                        dismiss()
                    }
                    .disabled(stop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: $showTargetPicker) {
            ArrivalTargetPickerView(
                cityName: stop.name,
                cityCoordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng),
                initialSelection: stop.arrivalTarget
            ) { target in
                stop.arrivalTarget = target
                if stop.stayDetails == nil {
                    let checkIn = stop.arrivalAt ?? Date()
                    stop.stayDetails = StayDetails(checkIn: checkIn, checkOut: Calendar.current.date(byAdding: .day, value: 1, to: checkIn))
                }
            }
        }
        .sheet(isPresented: $showTargetEditor) {
            if let target = stop.arrivalTarget {
                ArrivalTargetEditorView(
                    target: target,
                    stay: stop.stayDetails ?? StayDetails(),
                    routeId: routeId
                ) { target, stay in
                    stop.arrivalTarget = target
                    stop.stayDetails = stay
                }
            }
        }
    }
}
