import SwiftUI
import Foundation
import Combine
#if os(iOS)
import UIKit
import CoreLocation
#endif

// ... (unchanged code above)

// MARK: - Temporary placeholders to satisfy references in this file

final class AgAPI: ObservableObject {
    @Published var errorMessage: String? = nil
    var userID: UUID? = UUID()
    var teamID: UUID? = UUID()
    @Published var isLoading: Bool = false
    @Published var jobs: [SprayJobRow] = []

    private var chemicalsByJob: [UUID: [ChemicalRow]] = [:]

    // Jobs
    func deleteJob(_ job: SprayJobRow) async { }
    func upsertJob(_ row: SprayJobRow) async throws {
        await MainActor.run {
            if let idx = self.jobs.firstIndex(where: { $0.id == row.id }) {
                self.jobs[idx] = row
            } else {
                self.jobs.append(row)
            }
        }
    }
    func loadJobs() async throws {
        // No-op for in-memory placeholder; jobs already live in self.jobs
        await MainActor.run { self.isLoading = false }
    }
    
    // Placeholder for refreshAuthState and isAuthed to support new root view
    @Published var isAuthed: Bool = false
    func refreshAuthState() async {
        // Placeholder implementation
        isAuthed = true
    }
    
    // MARK: - Auth placeholders to satisfy LoginView
    func signIn(email: String, password: String) async {
        // Placeholder: pretend sign in succeeds
        await MainActor.run {
            self.errorMessage = nil
            self.isAuthed = true
            if self.userID == nil { self.userID = UUID() }
            if self.teamID == nil { self.teamID = UUID() }
        }
    }

    func signUp(email: String, password: String) async {
        // Placeholder: pretend sign up succeeds and signs in
        await MainActor.run {
            self.errorMessage = nil
            self.isAuthed = true
            if self.userID == nil { self.userID = UUID() }
            if self.teamID == nil { self.teamID = UUID() }
        }
    }

    func signOut() async {
        await MainActor.run {
            self.isAuthed = false
            self.userID = nil
            self.teamID = nil
        }
    }

    // Chemicals
    func loadChemicals(jobID: UUID) async throws -> [ChemicalRow] {
        return chemicalsByJob[jobID] ?? []
    }
    func replaceChemicals(jobID: UUID, drafts: [ChemicalDraft]) async throws {
        let rows: [ChemicalRow] = drafts.map { d in
            ChemicalRow(
                id: d.id,
                chemical_name: d.chemical_name.isEmpty ? nil : d.chemical_name,
                active_ingredient: d.active_ingredient.isEmpty ? nil : d.active_ingredient,
                rate_per_acre: d.rate_per_acre,
                rate_unit: d.rate_unit.rawValue,
                acres_applied: d.acres_applied
            )
        }
        chemicalsByJob[jobID] = rows
    }
}

struct SprayJobRow: Identifiable {
    var id: UUID
    var team_id: UUID
    var created_by: UUID
    var created_at: Date? = nil

    var field_name: String?
    var grower_name: String?
    var farm_owner_name: String?
    var address_line: String?
    var city: String?
    var state: String?
    var zip: String?
    var phone: String?
    var email: String?

    var latitude: Double?
    var longitude: Double?
    var weather_summary: String?

    var total_acres_sprayed: Double
    var start_time: String
    var end_time: String

    var wind_speed_mph: Double
    var wind_direction: String
    var humidity_percent: Double
    var dew_point_f: Double
    var pressure_inhg: Double
    var temperature_f: Double

    var notes: String?
}

struct ChemicalRow: Identifiable {
    var id: UUID = UUID()
    var chemical_name: String?
    var active_ingredient: String?
    var rate_per_acre: Double
    var rate_unit: String
    var acres_applied: Double
}

struct ChemicalDraft: Identifiable {
    var id: UUID = UUID()
    var chemical_name: String = ""
    var active_ingredient: String = ""
    var rate_per_acre: Double = 0
    var rate_unit: RateUnit = .gal_ac
    var acres_applied: Double = 0
}

enum RateUnit: String, CaseIterable, Identifiable {
    case gal_ac = "gal/ac"
    case oz_ac = "oz/ac"
    case pt_ac = "pt/ac"
    case qt_ac = "qt/ac"
    case lb_ac = "lb/ac"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

enum WindDirection: String, CaseIterable, Identifiable {
    case calm = "Calm"
    case N, NE, E, SE, S, SW, W, NW

    var id: String { rawValue }
}

#if os(iOS)
final class LocationWeatherService: NSObject, ObservableObject {
    @Published var isFetching: Bool = false
    @Published var errorMessage: String? = nil
    @Published var needsSettings: Bool = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
    }

    func openAppLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // Returns (address, weather)
    func fetchLocationAndWeather() async throws -> ((addressLine: String, city: String, state: String, zip: String, latitude: Double, longitude: Double), (summary: String, temperatureF: Double, humidityPercent: Double, dewPointF: Double, pressureInHg: Double, windSpeedMPH: Double, windDirection: WindDirection)) {
        await MainActor.run {
            self.errorMessage = nil
            self.isFetching = true
            self.needsSettings = false
        }
        defer { Task { await MainActor.run { self.isFetching = false } } }

        // Request authorization if needed
        if CLLocationManager.authorizationStatus() == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Give the system a moment to present the prompt
            try await Task.sleep(nanoseconds: 400_000_000)
        }

        let status = CLLocationManager.authorizationStatus()
        if status == .denied || status == .restricted {
            await MainActor.run {
                self.errorMessage = "Location access is denied. Enable it in Settings."
                self.needsSettings = true
            }
            throw NSError(domain: "LocationWeatherService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location permission denied"]) 
        }

        // Get a single location fix
        let location: CLLocation = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.manager.requestLocation()
            self._pendingContinuation = continuation
        }

        // Reverse geocode
        var addressLine = ""
        var city = ""
        var state = ""
        var zip = ""
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let pm = placemarks.first {
                addressLine = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
                city = pm.locality ?? ""
                state = pm.administrativeArea ?? ""
                zip = pm.postalCode ?? ""
            }
        } catch {
            // Non-fatal; keep defaults
        }

        let coords = (addressLine: addressLine, city: city, state: state, zip: zip, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

        // TODO: Integrate real weather provider here. For now, return placeholders to keep UI functional.
        let weather = (summary: "", temperatureF: 0.0, humidityPercent: 0.0, dewPointF: 0.0, pressureInHg: 29.92, windSpeedMPH: 0.0, windDirection: WindDirection.calm)

        return (coords, weather)
    }

    // MARK: - Private
    private var _pendingContinuation: CheckedContinuation<CLLocation, Error>? = nil
}

extension LocationWeatherService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            _pendingContinuation?.resume(returning: loc)
            _pendingContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        _pendingContinuation?.resume(throwing: error)
        _pendingContinuation = nil
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }
}
#else
final class LocationWeatherService: ObservableObject {
    @Published var isFetching: Bool = false
    @Published var errorMessage: String? = nil
    var needsSettings: Bool = false

    func openAppLocationSettings() { }

    // Returns (address, weather)
    func fetchLocationAndWeather() async throws -> ((addressLine: String, city: String, state: String, zip: String, latitude: Double, longitude: Double), (summary: String, temperatureF: Double, humidityPercent: Double, dewPointF: Double, pressureInHg: Double, windSpeedMPH: Double, windDirection: WindDirection)) {
        return (("", "", "", "", 0, 0), ("", 0, 0, 0, 29.92, 0, .calm))
    }
}
#endif

extension Date {
    static func fromISO(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso) ?? Date()
    }
    func iso() -> String {
        ISO8601DateFormatter().string(from: self)
    }
}

// MARK: - UserSettings and Formatting Helpers

enum WindSpeedUnit: String, CaseIterable, Identifiable {
    case mph, kph, mps, knots
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mph: return "mph"
        case .kph: return "km/h"
        case .mps: return "m/s"
        case .knots: return "kt"
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
}

enum PressureUnit: String, CaseIterable, Identifiable {
    case inhg, mb, atm, psi
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .inhg: return "inHg"
        case .mb: return "mb"
        case .atm: return "atm"
        case .psi: return "psi"
        }
    }
}

enum AreaUnit: String, CaseIterable, Identifiable {
    case acres, hectares
    var id: String { rawValue }
    var displayName: String { self == .acres ? "ac" : "ha" }
}

enum TimeFormat: String, CaseIterable, Identifiable {
    case twelveHour, twentyFourHour
    var id: String { rawValue }
    var displayName: String { self == .twelveHour ? "12-hour" : "24-hour" }
}

final class UserSettings: ObservableObject {
    @AppStorage("windUnit") var windUnitRaw: String = WindSpeedUnit.mph.rawValue
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.fahrenheit.rawValue
    @AppStorage("pressureUnit") var pressureUnitRaw: String = PressureUnit.inhg.rawValue
    @AppStorage("areaUnit") var areaUnitRaw: String = AreaUnit.acres.rawValue
    @AppStorage("timeFormat") var timeFormatRaw: String = TimeFormat.twelveHour.rawValue

    var windUnit: WindSpeedUnit { WindSpeedUnit(rawValue: windUnitRaw) ?? .mph }
    var temperatureUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .fahrenheit }
    var pressureUnit: PressureUnit { PressureUnit(rawValue: pressureUnitRaw) ?? .inhg }
    var areaUnit: AreaUnit { AreaUnit(rawValue: areaUnitRaw) ?? .acres }
    var timeFormat: TimeFormat { TimeFormat(rawValue: timeFormatRaw) ?? .twelveHour }
}

// MARK: - Formatting helpers
private func formatWindSpeed(mph: Double, settings: UserSettings) -> String {
    let v: Double; let unit: String
    switch settings.windUnit {
    case .mph: v = mph; unit = "mph"
    case .kph: v = mph * 1.609344; unit = "km/h"
    case .mps: v = mph * 0.44704; unit = "m/s"
    case .knots: v = mph * 0.868976; unit = "kt"
    }
    return "\(v.clean) \(unit)"
}

private func formatTemperature(fahrenheit: Double, settings: UserSettings) -> String {
    switch settings.temperatureUnit {
    case .fahrenheit: return "\(fahrenheit.clean) °F"
    case .celsius: return "\(((fahrenheit - 32.0) / 1.8).clean) °C"
    }
}

private func formatPressure(inHg: Double, settings: UserSettings) -> String {
    switch settings.pressureUnit {
    case .inhg: return "\(inHg.clean) inHg"
    case .mb: return "\((inHg * 33.8638866667).clean) mb"
    case .atm: return "\((inHg / 29.921252).clean) atm"
    case .psi: return "\((inHg * 0.491097).clean) psi"
    }
}

private func formatArea(acres: Double, settings: UserSettings) -> String {
    switch settings.areaUnit {
    case .acres: return "\(acres.clean) ac"
    case .hectares: return "\((acres * 0.40468564224).clean) ha"
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var settings: UserSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Area") {
                    Picker("Unit", selection: $settings.areaUnitRaw) {
                        ForEach(AreaUnit.allCases) { u in
                            Text(u.displayName).tag(u.rawValue)
                        }
                    }
                }
                Section("Wind Speed") {
                    Picker("Unit", selection: $settings.windUnitRaw) {
                        ForEach(WindSpeedUnit.allCases) { u in
                            Text(u.displayName).tag(u.rawValue)
                        }
                    }
                }
                Section("Temperature") {
                    Picker("Unit", selection: $settings.temperatureUnitRaw) {
                        ForEach(TemperatureUnit.allCases) { u in
                            Text(u.symbol).tag(u.rawValue)
                        }
                    }
                }
                Section("Pressure") {
                    Picker("Unit", selection: $settings.pressureUnitRaw) {
                        ForEach(PressureUnit.allCases) { u in
                            Text(u.displayName).tag(u.rawValue)
                        }
                    }
                }
                Section("Time Format") {
                    Picker("Format", selection: $settings.timeFormatRaw) {
                        ForEach(TimeFormat.allCases) { f in
                            Text(f.displayName).tag(f.rawValue)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct JobDetailView: View {
    @EnvironmentObject private var api: AgAPI
    @EnvironmentObject private var settings: UserSettings
    let job: SprayJobRow

    @State private var chems: [ChemicalRow] = []
    @State private var isLoading = false
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section("Job") {
                LabeledContent("Field", value: job.field_name ?? "—")
                LabeledContent("Grower", value: job.grower_name ?? "—")
                LabeledContent("Owner", value: job.farm_owner_name ?? "—")
                LabeledContent("Area", value: formatArea(acres: job.total_acres_sprayed, settings: settings))
                LabeledContent("Start", value: Date.fromISO(job.start_time).formatted(date: .abbreviated, time: .shortened))
                LabeledContent("End", value: Date.fromISO(job.end_time).formatted(date: .abbreviated, time: .shortened))
            }

            Section("Location") {
                LabeledContent("Address", value: job.address_line ?? "—")
                LabeledContent("City", value: job.city ?? "—")
                LabeledContent("State", value: job.state ?? "—")
                LabeledContent("ZIP", value: job.zip ?? "—")
                LabeledContent("Latitude", value: job.latitude?.clean ?? "—")
                LabeledContent("Longitude", value: job.longitude?.clean ?? "—")
            }

            Section("Contact") {
                LabeledContent("Phone", value: job.phone ?? "—")
                LabeledContent("Email", value: job.email ?? "—")
            }

            Section("Weather") {
                LabeledContent("Summary", value: job.weather_summary ?? "—")
                LabeledContent("Wind", value: "\(formatWindSpeed(mph: job.wind_speed_mph, settings: settings)) \(job.wind_direction)")
                LabeledContent("Humidity", value: "\(job.humidity_percent.clean)%")
                LabeledContent("Dew Point", value: formatTemperature(fahrenheit: job.dew_point_f, settings: settings))
                LabeledContent("Pressure", value: formatPressure(inHg: job.pressure_inhg, settings: settings))
                LabeledContent("Temperature", value: formatTemperature(fahrenheit: job.temperature_f, settings: settings))
            }

            Section("Chemicals") {
                if isLoading {
                    ProgressView()
                } else if chems.isEmpty {
                    Text("No chemicals logged.").foregroundStyle(.secondary)
                } else {
                    ForEach(chems) { c in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(c.chemical_name ?? "Chemical").font(.headline)

                            if let ai = c.active_ingredient, !ai.isEmpty {
                                Text("AI: \(ai)").foregroundStyle(.secondary)
                            }

                            Text("Rate: \(c.rate_per_acre.clean) \(c.rate_unit) • Acres: \(c.acres_applied.clean)")
                                .foregroundStyle(.secondary)

                            Text("Total: \(chemTotal(c))").fontWeight(.semibold)
                        }
                        .padding(.vertical, 6)
                    }

                    let totals = chemTotals(chems)
                    if totals.gal > 0 {
                        LabeledContent("Total gallons", value: "\(totals.gal.clean) gal")
                    }
                    if totals.oz > 0 {
                        LabeledContent("Total ounces", value: "\(totals.oz.clean) oz (\((totals.oz / 128.0).clean) gal eq)")
                    }
                    if totals.lb > 0 {
                        LabeledContent("Total pounds", value: "\(totals.lb.clean) lb")
                    }
                }
            }

            if let notes = job.notes, !notes.isEmpty {
                Section("Notes") { Text(notes) }
            }
        }
        .navigationTitle(job.field_name ?? "Record")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this spray job?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task { await api.deleteJob(job) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                JobEditorView(existing: job)
            }
        }
        .task { await loadChemicals() }
    }

    private func loadChemicals() async {
        isLoading = true
        defer { isLoading = false }

        do {
            chems = try await api.loadChemicals(jobID: job.id)
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }

    private func chemTotal(_ c: ChemicalRow) -> String {
        let acres = max(0, c.acres_applied)
        let rate = max(0, c.rate_per_acre)

        if c.rate_unit == RateUnit.gal_ac.rawValue {
            return "\(((rate * acres).clean)) gal".replacingOccurrences(of: "((", with: "(").replacingOccurrences(of: "))", with: ")")
        } else if c.rate_unit == RateUnit.oz_ac.rawValue {
            let oz = rate * acres
            return "\(oz.clean) oz (\(((oz / 128.0).clean)) gal eq)".replacingOccurrences(of: "((", with: "(").replacingOccurrences(of: "))", with: ")")
        } else if c.rate_unit == RateUnit.pt_ac.rawValue {
            let totalPt = rate * acres
            let gal = totalPt / 8.0
            return "\(totalPt.clean) pt (\(gal.clean) gal eq)"
        } else if c.rate_unit == RateUnit.qt_ac.rawValue {
            let totalQt = rate * acres
            let gal = totalQt / 4.0
            return "\(totalQt.clean) qt (\(gal.clean) gal eq)"
        } else if c.rate_unit == RateUnit.lb_ac.rawValue {
            let lb = rate * acres
            return "\(lb.clean) lb (oz eq requires density)"
        } else {
            let oz = rate * acres
            return "\(oz.clean) oz"
        }
    }

    private func chemTotals(_ rows: [ChemicalRow]) -> (gal: Double, oz: Double, lb: Double) {
        var gal = 0.0
        var oz = 0.0
        var lb = 0.0

        for r in rows {
            let acres = max(0, r.acres_applied)
            let rate = max(0, r.rate_per_acre)

            if r.rate_unit == RateUnit.gal_ac.rawValue {
                gal += rate * acres
            } else if r.rate_unit == RateUnit.oz_ac.rawValue {
                oz += rate * acres
            } else if r.rate_unit == RateUnit.pt_ac.rawValue {
                gal += (rate * acres) / 8.0
            } else if r.rate_unit == RateUnit.qt_ac.rawValue {
                gal += (rate * acres) / 4.0
            } else if r.rate_unit == RateUnit.lb_ac.rawValue {
                lb += rate * acres
            }
        }

        return (gal, oz, lb)
    }
}

// MARK: - Reusable Rows

private struct NumberRow: View {
    let title: String
    @Binding var value: Double
    let suffix: String

    @State private var text: String = ""

    init(title: String, value: Binding<Double>, suffix: String) {
        self.title = title
        self._value = value
        self.suffix = suffix
        self._text = State(initialValue: value.wrappedValue.clean)
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                TextField("0", text: $text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .onChange(of: text) { _, newValue in
                        // Sanitize input and update bound Double
                        let filtered = newValue.replacingOccurrences(of: ",", with: "")
                        if let d = Double(filtered) {
                            value = d
                        }
                    }
                    .frame(minWidth: 60)
                if !suffix.isEmpty {
                    Text(suffix).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: value) { _, newVal in
            // Keep text in sync when external value changes
            text = newVal.clean
        }
    }
}

private extension Double {
    var clean: String {
        if self.isNaN || self.isInfinite { return "0" }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}

// MARK: - Editor

struct JobEditorView: View {
    @EnvironmentObject private var api: AgAPI
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationWeather = LocationWeatherService()

    let existing: SprayJobRow?

    @State private var fieldName = ""
    @State private var growerName = ""
    @State private var ownerName = ""
    @State private var addressLine = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var phone = ""
    @State private var email = ""

    @State private var latitude: Double = 0
    @State private var longitude: Double = 0
    @State private var hasCoordinate = false
    @State private var weatherSummary = ""

    @State private var totalAcres: Double = 0
    @State private var startTime: Date = .now
    @State private var endTime: Date = .now

    @State private var windSpeed: Double = 0
    @State private var windDir: WindDirection = .calm
    @State private var humidity: Double = 0
    @State private var dewPoint: Double = 0
    @State private var pressure: Double = 29.92
    @State private var temperature: Double = 0

    @State private var notes = ""

    @State private var chemicals: [ChemicalDraft] = [ChemicalDraft()] // each has unique id
    @State private var isBusy = false

    var body: some View {
        Form {
            Section("Field / Contact") {
                TextField("Field name / ID", text: $fieldName)
                TextField("Grower name", text: $growerName)
                TextField("Farm owner name", text: $ownerName)

                TextField("Address line", text: $addressLine)
                TextField("City", text: $city)
                TextField("State", text: $state)
                TextField("ZIP", text: $zip)

                TextField("Phone", text: $phone)
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
            }

            Section("GPS / Auto Fill") {
                Button(locationWeather.isFetching ? "Fetching..." : "Use Current Location & Weather") {
                    Task { await fillFromLocationAndWeather() }
                }
                .disabled(locationWeather.isFetching)

                if hasCoordinate {
                    LabeledContent("Latitude", value: latitude.clean)
                    LabeledContent("Longitude", value: longitude.clean)
                }

                if let locationError = locationWeather.errorMessage, !locationError.isEmpty {
                    Text(locationError).foregroundStyle(.red)
                    if locationWeather.needsSettings {
                        Button("Open Settings") {
                            locationWeather.openAppLocationSettings()
                        }
                    }
                }
            }

            Section("Acres & Time") {
                NumberRow(title: "Total acres sprayed", value: $totalAcres, suffix: "ac")
                DatePicker("Start", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
            }

            Section("Weather") {
                TextField("Weather summary", text: $weatherSummary)
                NumberRow(title: "Wind speed", value: $windSpeed, suffix: "mph")

                Picker("Wind direction", selection: $windDir) {
                    ForEach(WindDirection.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }

                NumberRow(title: "Humidity", value: $humidity, suffix: "%")
                NumberRow(title: "Dew point", value: $dewPoint, suffix: "°F")
                NumberRow(title: "Pressure", value: $pressure, suffix: "inHg")
                NumberRow(title: "Temperature", value: $temperature, suffix: "°F")
            }

            Section("Chemicals (up to 5)") {
                ForEach($chemicals, id: \.id) { $c in
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Chemical name", text: $c.chemical_name)
                        TextField("Active ingredient", text: $c.active_ingredient)

                        HStack(spacing: 12) {
                            NumberRow(title: "Rate", value: $c.rate_per_acre, suffix: "")

                            Picker("Rate Unit", selection: $c.rate_unit) {
                                ForEach(RateUnit.allCases) { u in
                                    Text(u.displayName).tag(u)
                                }
                            }
                            .labelsHidden()
                        }

                        NumberRow(title: "Acres applied", value: $c.acres_applied, suffix: "ac")

                        HStack {
                            Text("Total").foregroundStyle(.secondary)
                            Spacer()
                            Text(chemDraftTotal(c)).fontWeight(.semibold)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { idx in
                    chemicals.remove(atOffsets: idx)
                }

                Button {
                    guard chemicals.count < 5 else { return }
                    var new = ChemicalDraft()
                    new.acres_applied = max(0, totalAcres)
                    chemicals.append(new)
                } label: {
                    Label("Add Chemical", systemImage: "plus")
                }
                .disabled(chemicals.count >= 5)
            }

            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 110)
            }

            if let msg = api.errorMessage {
                Section {
                    Text(msg).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(existing == nil ? "New Spray Job" : "Edit Spray Job")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isBusy ? "Saving..." : "Save") {
                    Task { await save() }
                }
                .disabled(isBusy)
            }
        }
        .onAppear { loadExisting() }
    }

    private func loadExisting() {
        guard let e = existing else { return }

        fieldName = e.field_name ?? ""
        growerName = e.grower_name ?? ""
        ownerName = e.farm_owner_name ?? ""
        addressLine = e.address_line ?? ""
        city = e.city ?? ""
        state = e.state ?? ""
        zip = e.zip ?? ""
        phone = e.phone ?? ""
        email = e.email ?? ""

        latitude = e.latitude ?? 0
        longitude = e.longitude ?? 0
        hasCoordinate = e.latitude != nil && e.longitude != nil
        weatherSummary = e.weather_summary ?? ""

        totalAcres = e.total_acres_sprayed
        startTime = Date.fromISO(e.start_time)
        endTime = Date.fromISO(e.end_time)

        windSpeed = e.wind_speed_mph
        windDir = WindDirection(rawValue: e.wind_direction) ?? .calm
        humidity = e.humidity_percent
        dewPoint = e.dew_point_f
        pressure = e.pressure_inhg
        temperature = e.temperature_f

        notes = e.notes ?? ""

        Task {
            do {
                let rows = try await api.loadChemicals(jobID: e.id)
                await MainActor.run {
                    if rows.isEmpty {
                        chemicals = [ChemicalDraft(acres_applied: max(0, totalAcres))]
                    } else {
                        chemicals = rows.map {
                            ChemicalDraft(
                                id: $0.id,
                                chemical_name: $0.chemical_name ?? "",
                                active_ingredient: $0.active_ingredient ?? "",
                                rate_per_acre: $0.rate_per_acre,
                                rate_unit: RateUnit(rawValue: $0.rate_unit) ?? .gal_ac,
                                acres_applied: $0.acres_applied
                            )
                        }
                    }
                }
            } catch {
                api.errorMessage = error.localizedDescription
            }
        }
    }

    private func fillFromLocationAndWeather() async {
        do {
            let result = try await locationWeather.fetchLocationAndWeather()

            addressLine = result.0.addressLine
            city = result.0.city
            state = result.0.state
            zip = result.0.zip
            latitude = result.0.latitude
            longitude = result.0.longitude
            hasCoordinate = true

            weatherSummary = result.1.summary
            temperature = result.1.temperatureF
            humidity = result.1.humidityPercent
            dewPoint = result.1.dewPointF
            pressure = result.1.pressureInHg
            windSpeed = result.1.windSpeedMPH
            windDir = result.1.windDirection
        } catch {
            locationWeather.errorMessage = error.localizedDescription
        }
    }

    private func chemDraftTotal(_ c: ChemicalDraft) -> String {
        let acres = max(0, c.acres_applied)
        let rate = max(0, c.rate_per_acre)

        if c.rate_unit == .gal_ac {
            return "\(((rate * acres).clean)) gal".replacingOccurrences(of: "((", with: "(").replacingOccurrences(of: "))", with: ")")
        } else if c.rate_unit == .oz_ac {
            let oz = rate * acres
            return "\(oz.clean) oz (\(((oz / 128.0).clean)) gal eq)".replacingOccurrences(of: "((", with: "(").replacingOccurrences(of: "))", with: ")")
        } else if c.rate_unit == .pt_ac {
            let totalPt = rate * acres
            let gal = totalPt / 8.0
            return "\(totalPt.clean) pt (\(gal.clean) gal eq)"
        } else if c.rate_unit == .qt_ac {
            let totalQt = rate * acres
            let gal = totalQt / 4.0
            return "\(totalQt.clean) qt (\(gal.clean) gal eq)"
        } else if c.rate_unit == .lb_ac {
            let lb = rate * acres
            return "\(lb.clean) lb (oz eq requires density)"
        } else {
            let oz = rate * acres
            return "\(oz.clean) oz"
        }
    }

    private func save() async {
        api.errorMessage = nil

        guard let uid = api.userID else {
            api.errorMessage = "Not logged in."
            return
        }

        guard let teamID = api.teamID else {
            api.errorMessage = "No team membership found."
            return
        }

        isBusy = true
        defer { isBusy = false }

        let id = existing?.id ?? UUID()

        let row = SprayJobRow(
            id: id,
            team_id: teamID,
            created_by: existing?.created_by ?? uid,
            created_at: existing?.created_at,

            field_name: fieldName.isEmpty ? nil : fieldName,
            grower_name: growerName.isEmpty ? nil : growerName,
            farm_owner_name: ownerName.isEmpty ? nil : ownerName,
            address_line: addressLine.isEmpty ? nil : addressLine,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            zip: zip.isEmpty ? nil : zip,
            phone: phone.isEmpty ? nil : phone,
            email: email.isEmpty ? nil : email,

            latitude: hasCoordinate ? latitude : nil,
            longitude: hasCoordinate ? longitude : nil,
            weather_summary: weatherSummary.isEmpty ? nil : weatherSummary,

            total_acres_sprayed: max(0, totalAcres),
            start_time: startTime.iso(),
            end_time: endTime.iso(),

            wind_speed_mph: max(0, windSpeed),
            wind_direction: windDir.rawValue,
            humidity_percent: max(0, humidity),
            dew_point_f: dewPoint,
            pressure_inhg: pressure,
            temperature_f: temperature,

            notes: notes.isEmpty ? nil : notes
        )

        do {
            try await api.upsertJob(row)

            var finalDrafts = chemicals
            for i in finalDrafts.indices {
                if finalDrafts[i].acres_applied <= 0 {
                    finalDrafts[i].acres_applied = max(0, totalAcres)
                }
            }

            finalDrafts = Array(finalDrafts.prefix(5)).filter {
                !$0.chemical_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !$0.active_ingredient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                $0.rate_per_acre != 0
            }

            try await api.replaceChemicals(jobID: id, drafts: finalDrafts)
            try await api.loadJobs()
            dismiss()
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - LoginView replacement

struct LoginView: View {
    @EnvironmentObject private var api: AgAPI

    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Company Login") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)

                    SecureField("Password", text: $password)
                }

                if let msg = api.errorMessage, !msg.isEmpty {
                    Section { Text(msg).foregroundStyle(.red) }
                }

                Section {
                    Button("Sign In") {
                        Task {
                            isBusy = true
                            defer { isBusy = false }
                            await api.signIn(email: email, password: password)
                        }
                    }
                    .disabled(isBusy || email.isEmpty || password.isEmpty)

                    Button("Create Account") {
                        Task {
                            isBusy = true
                            defer { isBusy = false }
                            await api.signUp(email: email, password: password)
                        }
                    }
                    .disabled(isBusy || email.isEmpty || password.isEmpty)
                }

                Section("First-time setup") {
                    Text("""
If you see “No team membership found”, create a team and add your user to team_members (one-time) in Supabase SQL.
After that, everyone added to the same team will share the same jobs.
""")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ag Tracker")
        }
    }
}

// Minimal placeholder for MainView to satisfy RootView reference


struct MainView: View {
    @EnvironmentObject private var api: AgAPI
    @EnvironmentObject private var settings: UserSettings

    @State private var showingNew = false
    @State private var selectedDate: Date = .now
    @State private var pdfURL: URL?
    @State private var showingDaily = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .font(.headline)
                    }
                }
                
                if api.isLoading {
                    ProgressView().frame(maxWidth: .infinity, alignment: .center)
                }

                ForEach(api.jobs) { job in
                    NavigationLink {
                        JobDetailView(job: job)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text((job.field_name?.isEmpty == false) ? job.field_name! : "Unnamed Field")
                                .font(.headline)
                            Text("\(formatArea(acres: job.total_acres_sprayed, settings: settings)) • \(Date.fromISO(job.start_time).formatted(date: .abbreviated, time: .shortened))")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .onDelete { idx in
                    Task {
                        for i in idx {
                            await api.deleteJob(api.jobs[i])
                        }
                    }
                }
            }
            .navigationTitle("Ag Tracker")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Daily PDF") { showingDaily = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") { Task { await api.signOut() } }
                }
            }
            .sheet(isPresented: $showingNew) {
                NavigationStack {
                    JobEditorView(existing: nil)
                }
            }
            .sheet(isPresented: $showingDaily) {
                NavigationStack {
                    Form {
                        DatePicker("Select day", selection: $selectedDate, displayedComponents: .date)
                        Button("Generate PDF") {
                            Task { await generateDailyPDF() }
                        }
                        if let pdfURL {
                            ShareLink(item: pdfURL) {
                                Label("Share PDF", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .navigationTitle("Daily Summary")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingDaily = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .refreshable {
                do { try await api.loadJobs() } catch { api.errorMessage = error.localizedDescription }
            }
        }
    }

    private func generateDailyPDF() async {
        api.errorMessage = nil
        pdfURL = nil
        do {
            let cal = Calendar.current
            let dayJobs = api.jobs.filter { cal.isDate(Date.fromISO($0.start_time), inSameDayAs: selectedDate) }

            var chemsByJob: [UUID: [ChemicalRow]] = [:]
            for j in dayJobs {
                let chems = try await api.loadChemicals(jobID: j.id)
                chemsByJob[j.id] = chems
            }

            pdfURL = try makeDailySummaryPDF(date: selectedDate, jobs: dayJobs, chemsByJob: chemsByJob)
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }
}

// ... (unchanged code below)


// MARK: - PDF Generation Helper

private func makeDailySummaryPDF(date: Date, jobs: [SprayJobRow], chemsByJob: [UUID: [ChemicalRow]]) throws -> URL {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    let settings = UserSettings()

    // Create a temporary file URL
    let fileName = "Daily_Summary_\(formatter.string(from: date)).pdf".replacingOccurrences(of: " ", with: "_")
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

    #if os(iOS)
    // Page setup
    let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter: 8.5x11 at 72dpi
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

    let data = renderer.pdfData { ctx in
        ctx.beginPage()
        let ctxRef = UIGraphicsGetCurrentContext()
        ctxRef?.setFillColor(UIColor.white.cgColor)
        ctxRef?.fill(pageRect)

        var cursorY: CGFloat = 40
        let leftMargin: CGFloat = 36
        let rightMargin: CGFloat = 36
        let contentWidth = pageRect.width - leftMargin - rightMargin

        // Title
        let title = "Daily Spray Summary"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 22)
        ]
        (title as NSString).draw(in: CGRect(x: leftMargin, y: cursorY, width: contentWidth, height: 28), withAttributes: titleAttrs)
        cursorY += 30

        // Date
        let dateLine = formatter.string(from: date)
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.darkGray
        ]
        (dateLine as NSString).draw(in: CGRect(x: leftMargin, y: cursorY, width: contentWidth, height: 20), withAttributes: dateAttrs)
        cursorY += 28

        // Divider
        ctxRef?.setFillColor(UIColor.lightGray.cgColor)
        ctxRef?.fill(CGRect(x: leftMargin, y: cursorY, width: contentWidth, height: 1))
        cursorY += 12

        let bodyFont = UIFont.systemFont(ofSize: 12)
        let boldFont = UIFont.boldSystemFont(ofSize: 12)

        func drawLine(_ text: String, bold: Bool = false, extraSpacing: CGFloat = 4) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? boldFont : bodyFont,
                .foregroundColor: UIColor.black
            ]
            (text as NSString).draw(in: CGRect(x: leftMargin, y: cursorY, width: contentWidth, height: 18), withAttributes: attrs)
            cursorY += 18 + extraSpacing
        }

        // Jobs content
        if jobs.isEmpty {
            drawLine("No jobs for this day.")
        } else {
            for job in jobs {
                // Job header
                let field = (job.field_name?.isEmpty == false) ? job.field_name! : "Unnamed Field"
                drawLine("Field: \(field)", bold: true, extraSpacing: 2)

                let start = Date.fromISO(job.start_time).formatted(date: .abbreviated, time: .shortened)
                let acres = job.total_acres_sprayed.clean
                drawLine("Start: \(start)    Acres: \(acres)")
                
                let city = job.city?.isEmpty == false ? job.city! : "—"
                let state = job.state?.isEmpty == false ? job.state! : "—"
                let latText = job.latitude != nil ? job.latitude!.clean : "—"
                let lonText = job.longitude != nil ? job.longitude!.clean : "—"
                drawLine("Location: \(city), \(state)  |  Lat: \(latText)  Lon: \(lonText)")

                // Weather snapshot
                let wind = "\(formatWindSpeed(mph: job.wind_speed_mph, settings: settings)) \(job.wind_direction)"
                drawLine("Weather: \(job.weather_summary ?? "—")")
                let weatherDetails = "Wind: \(wind) | Temp: \(formatTemperature(fahrenheit: job.temperature_f, settings: settings)) | Humidity: \(job.humidity_percent.clean)% | Dew Pt: \(formatTemperature(fahrenheit: job.dew_point_f, settings: settings)) | Pressure: \(formatPressure(inHg: job.pressure_inhg, settings: settings))"
                drawLine(weatherDetails)

                // Chemicals for job
                if let chems = chemsByJob[job.id], !chems.isEmpty {
                    drawLine("Chemicals:", bold: true)
                    for c in chems {
                        let name = c.chemical_name ?? "Chemical"
                        var line = "• \(name) — Rate: \(c.rate_per_acre.clean) \(c.rate_unit)  Acres: \(c.acres_applied.clean)"
                        if let ai = c.active_ingredient, !ai.isEmpty {
                            line += "  (AI: \(ai))"
                        }
                        drawLine(line, extraSpacing: 2)
                    }
                } else {
                    drawLine("No chemicals recorded.")
                }

                // Section spacing
                cursorY += 8

                // Page break if needed
                if cursorY > pageRect.height - 72 {
                    ctx.beginPage()
                    cursorY = 40
                }
            }
        }
    }

    try data.write(to: tempURL)
    return tempURL
    #else
    // Fallback for non-iOS platforms: write a simple text file with .pdf extension
    let content = "Daily Spray Summary\n\nDate: \(formatter.string(from: date))\nJobs: \(jobs.count)\n"
    try content.data(using: .utf8)?.write(to: tempURL)
    return tempURL
    #endif
}

@main
struct AgTrackerSupabaseApp: App {
    @StateObject private var api = AgAPI()
    @StateObject private var settings = UserSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
                .environmentObject(settings)
                .task { await api.refreshAuthState() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var api: AgAPI

    var body: some View {
        if api.isAuthed {
            MainView()
        } else {
            LoginView()
        }
    }
}

