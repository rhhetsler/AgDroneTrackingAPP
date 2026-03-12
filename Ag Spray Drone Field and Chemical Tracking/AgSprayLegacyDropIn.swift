import SwiftUI
import Foundation
import Combine
import UIKit
import Supabase
import CoreLocation

// ======================================================
// AG TRACKER — SINGLE DROP-IN FILE
// ======================================================

// MARK: - Supabase Config
let supabaseURL = URL(string: "https://rocobuoemdaevzgdzpnv.supabase.co")!
let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJvY29idW9lbWRhZXZ6Z2R6cG52Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE2MjQ4NzcsImV4cCI6MjA4NzIwMDg3N30.oK7eCKo8bNK2ovXsZLM5V30KzlSp_E1-q5xjNhz0pfI"

// MARK: - Helpers

extension Double {
    var clean: String {
        if self.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        }
        return String(format: "%.2f", self)
    }
}

extension Optional where Wrapped == Double {
    var cleanOrBlank: String {
        guard let value = self else { return "" }
        return value.clean
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension DateFormatter {
    static let shortDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

enum RateUnit: String, Codable, CaseIterable, Identifiable {
    case gal_ac = "gal_ac"
    case oz_ac = "oz_ac"
    case pt_ac = "pt_ac"
    case qt_ac = "qt_ac"
    case lb_ac = "lb_ac"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gal_ac: return "gal/ac"
        case .oz_ac: return "oz/ac"
        case .pt_ac: return "pt/ac"
        case .qt_ac: return "qt/ac"
        case .lb_ac: return "lb/ac"
        }
    }
}

// MARK: - Models

struct TeamMemberRow: Codable, Identifiable {
    let id: UUID?
    let team_id: UUID
    let user_id: UUID
    let role: String?
}

struct SprayJobRow: Codable, Identifiable, Hashable {
    let id: UUID
    let team_id: UUID
    var created_by: UUID?

    var job_name: String?
    var field_name: String?
    var farm_name: String?
    var crop: String?
    var total_acres_sprayed: Double
    var spray_date: String?
    var notes: String?
    var is_closed: Bool?

    var temperature_f: Double?
    var humidity_percent: Double?
    var wind_speed_mph: Double?
    var wind_direction: String?
    var barometric_pressure_inhg: Double?
    var dew_point_f: Double?

    var location_name: String?
    var weather_summary: String?
    var created_at: String?

    init(
        id: UUID = UUID(),
        team_id: UUID,
        created_by: UUID? = nil,
        job_name: String? = nil,
        field_name: String? = nil,
        farm_name: String? = nil,
        crop: String? = nil,
        total_acres_sprayed: Double = 0,
        spray_date: String? = nil,
        notes: String? = nil,
        is_closed: Bool? = false,
        temperature_f: Double? = nil,
        humidity_percent: Double? = nil,
        wind_speed_mph: Double? = nil,
        wind_direction: String? = nil,
        barometric_pressure_inhg: Double? = nil,
        dew_point_f: Double? = nil,
        location_name: String? = nil,
        weather_summary: String? = nil,
        created_at: String? = nil
    ) {
        self.id = id
        self.team_id = team_id
        self.created_by = created_by
        self.job_name = job_name
        self.field_name = field_name
        self.farm_name = farm_name
        self.crop = crop
        self.total_acres_sprayed = total_acres_sprayed
        self.spray_date = spray_date
        self.notes = notes
        self.is_closed = is_closed
        self.temperature_f = temperature_f
        self.humidity_percent = humidity_percent
        self.wind_speed_mph = wind_speed_mph
        self.wind_direction = wind_direction
        self.barometric_pressure_inhg = barometric_pressure_inhg
        self.dew_point_f = dew_point_f
        self.location_name = location_name
        self.weather_summary = weather_summary
        self.created_at = created_at
    }
}

struct ChemicalRow: Codable, Identifiable, Hashable {
    let id: UUID
    let spray_job_id: UUID
    var chemical_name: String?
    var active_ingredient: String?
    var rate_per_acre: Double
    var rate_unit: String
    var acres_applied: Double
}

struct ChemicalDraft: Identifiable, Hashable {
    let id = UUID()
    var chemical_name: String = ""
    var active_ingredient: String = ""
    var rate_per_acre: Double = 0
    var rate_unit: RateUnit = .oz_ac
    var acres_applied: Double = 0
}

// MARK: - AgAPI

@MainActor
final class AgAPI: ObservableObject {
    let client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseAnonKey)

    @Published var isAuthed: Bool = false
    @Published var userID: UUID?
    @Published var teamID: UUID?
    @Published var teamRole: String?

    @Published var jobs: [SprayJobRow] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func handleAuthCallback(_ url: URL) async {
        errorMessage = nil
        do {
            _ = try await client.auth.session(from: url)
            await refreshAuthState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAuthState() async {
        do {
            let session = try await client.auth.session
            self.isAuthed = true
            self.userID = session.user.id
            try await loadTeamMembership()
            try await loadJobs()
        } catch {
            self.isAuthed = false
            self.userID = nil
            self.teamID = nil
            self.teamRole = nil
            self.jobs = []
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            try await refreshAuthState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            try await refreshAuthState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        errorMessage = nil
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshAuthState()
    }

    func loadTeamMembership() async throws {
        guard let uid = try? await client.auth.session.user.id else {
            throw NSError(domain: "AgTracker", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not logged in."
            ])
        }

        let rows: [TeamMemberRow] = try await client
            .from("team_members")
            .select()
            .eq("user_id", value: uid.uuidString)
            .limit(1)
            .execute()
            .value

        guard let first = rows.first else {
            self.teamID = nil
            self.teamRole = nil
            throw NSError(domain: "AgTracker", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "No team membership found. Add this user to team_members in Supabase."
            ])
        }

        self.teamID = first.team_id
        self.teamRole = first.role
        self.userID = uid
    }

    func loadJobs() async throws {
        guard let teamID else { return }
        isLoading = true
        defer { isLoading = false }

        let rows: [SprayJobRow] = try await client
            .from("spray_jobs")
            .select()
            .eq("team_id", value: teamID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        self.jobs = rows
    }

    func upsertJob(_ job: SprayJobRow) async throws {
        _ = try await client
            .from("spray_jobs")
            .upsert(job)
            .execute()

        try await loadJobs()
    }

    func deleteJob(_ job: SprayJobRow) async {
        errorMessage = nil
        do {
            try await client
                .from("spray_jobs")
                .delete()
                .eq("id", value: job.id.uuidString)
                .execute()

            try await loadJobs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadChemicals(jobID: UUID) async throws -> [ChemicalRow] {
        let rows: [ChemicalRow] = try await client
            .from("chemical_entries")
            .select()
            .eq("spray_job_id", value: jobID.uuidString)
            .execute()
            .value

        return rows
    }

    func replaceChemicals(jobID: UUID, drafts: [ChemicalDraft]) async throws {
        try await client
            .from("chemical_entries")
            .delete()
            .eq("spray_job_id", value: jobID.uuidString)
            .execute()

        let payload = drafts.map {
            ChemicalRow(
                id: UUID(),
                spray_job_id: jobID,
                chemical_name: $0.chemical_name.nilIfEmpty,
                active_ingredient: $0.active_ingredient.nilIfEmpty,
                rate_per_acre: max(0, $0.rate_per_acre),
                rate_unit: $0.rate_unit.rawValue,
                acres_applied: max(0, $0.acres_applied)
            )
        }

        if !payload.isEmpty {
            _ = try await client
                .from("chemical_entries")
                .insert(payload)
                .execute()
        }
    }
}

// MARK: - PDF Helpers

private struct DailyTotals {
    var acres: Double = 0
    var gallons: Double = 0
    var ounces: Double = 0
    var pints: Double = 0
    var quarts: Double = 0
    var pounds: Double = 0
    var byChemical: [String: (acres: Double, gal: Double, oz: Double, pt: Double, qt: Double, lb: Double)] = [:]
}

private func makeDailySummaryPDF(date: Date, jobs: [SprayJobRow], chemsByJob: [UUID: [ChemicalRow]]) throws -> URL {
    var totals = DailyTotals()

    for j in jobs {
        totals.acres += max(0, j.total_acres_sprayed)
        let chems = chemsByJob[j.id] ?? []

        for c in chems {
            let name = (c.chemical_name?.isEmpty == false) ? c.chemical_name! : "Chemical"
            let acres = max(0, c.acres_applied)
            let rate = max(0, c.rate_per_acre)

            var gal = 0.0
            var oz = 0.0
            var pt = 0.0
            var qt = 0.0
            var lb = 0.0

            switch c.rate_unit {
            case RateUnit.gal_ac.rawValue: gal = rate * acres
            case RateUnit.oz_ac.rawValue: oz = rate * acres
            case RateUnit.pt_ac.rawValue: pt = rate * acres
            case RateUnit.qt_ac.rawValue: qt = rate * acres
            case RateUnit.lb_ac.rawValue: lb = rate * acres
            default: oz = rate * acres
            }

            totals.gallons += gal
            totals.ounces += oz
            totals.pints += pt
            totals.quarts += qt
            totals.pounds += lb

            var bucket = totals.byChemical[name] ?? (0, 0, 0, 0, 0, 0)
            bucket.acres += acres
            bucket.gal += gal
            bucket.oz += oz
            bucket.pt += pt
            bucket.qt += qt
            bucket.lb += lb
            totals.byChemical[name] = bucket
        }
    }

    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: page)

    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgTracker_DailySummary_\(date.formatted(.iso8601.year().month().day())).pdf")

    try renderer.writePDF(to: fileURL) { ctx in
        ctx.beginPage()

        let margin: CGFloat = 36
        var y: CGFloat = margin

        func draw(_ text: String, font: UIFont, spacing: CGFloat = 6) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let width = page.width - margin * 2
            let rect = CGRect(x: margin, y: y, width: width, height: 2000)

            let h = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            ).height

            (text as NSString).draw(
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                withAttributes: attrs
            )
            y += h + spacing
        }

        draw("Ag Tracker - Daily Summary", font: .boldSystemFont(ofSize: 22), spacing: 10)
        draw(date.formatted(date: .long, time: .omitted), font: .systemFont(ofSize: 14), spacing: 16)

        draw("Totals", font: .boldSystemFont(ofSize: 16), spacing: 8)
        draw("Acres sprayed: \(totals.acres.clean) ac", font: .systemFont(ofSize: 12))
        draw("Gallons: \(totals.gallons.clean) gal", font: .systemFont(ofSize: 12))
        draw("Ounces: \(totals.ounces.clean) oz", font: .systemFont(ofSize: 12))
        draw("Pints: \(totals.pints.clean) pt", font: .systemFont(ofSize: 12))
        draw("Quarts: \(totals.quarts.clean) qt", font: .systemFont(ofSize: 12))
        draw("Pounds: \(totals.pounds.clean) lb", font: .systemFont(ofSize: 12))

        y += 12
        draw("Jobs", font: .boldSystemFont(ofSize: 16), spacing: 8)

        if jobs.isEmpty {
            draw("No jobs logged.", font: .systemFont(ofSize: 12))
        } else {
            for job in jobs {
                draw("• \(job.job_name ?? "Untitled Job")", font: .boldSystemFont(ofSize: 13), spacing: 4)
                draw("  Acres: \(job.total_acres_sprayed.clean) ac", font: .systemFont(ofSize: 11), spacing: 2)

                var wxParts: [String] = []
                if let temp = job.temperature_f { wxParts.append("Temp \(temp.clean)°F") }
                if let rh = job.humidity_percent { wxParts.append("RH \(rh.clean)%") }
                if let wind = job.wind_speed_mph { wxParts.append("Wind \(wind.clean) mph") }
                if let dir = job.wind_direction, !dir.isEmpty { wxParts.append(dir) }
                if let bp = job.barometric_pressure_inhg { wxParts.append("Pressure \(bp.clean) inHg") }
                if let dew = job.dew_point_f { wxParts.append("Dew Pt \(dew.clean)°F") }

                if !wxParts.isEmpty {
                    draw("  " + wxParts.joined(separator: " | "), font: .systemFont(ofSize: 11), spacing: 2)
                }

                if let loc = job.location_name, !loc.isEmpty {
                    draw("  Location: \(loc)", font: .systemFont(ofSize: 11), spacing: 2)
                }

                if let summary = job.weather_summary, !summary.isEmpty {
                    draw("  Weather: \(summary)", font: .systemFont(ofSize: 11), spacing: 6)
                }
            }
        }

        y += 8
        draw("By Chemical", font: .boldSystemFont(ofSize: 16), spacing: 8)

        let keys = totals.byChemical.keys.sorted()
        if keys.isEmpty {
            draw("No chemicals logged.", font: .systemFont(ofSize: 12))
        } else {
            for key in keys {
                let b = totals.byChemical[key]!
                var parts: [String] = ["\(b.acres.clean) ac"]
                if b.gal > 0 { parts.append("\(b.gal.clean) gal") }
                if b.oz > 0 { parts.append("\(b.oz.clean) oz") }
                if b.pt > 0 { parts.append("\(b.pt.clean) pt") }
                if b.qt > 0 { parts.append("\(b.qt.clean) qt") }
                if b.lb > 0 { parts.append("\(b.lb.clean) lb") }

                draw("• \(key): " + parts.joined(separator: ", "), font: .systemFont(ofSize: 12))
            }
        }
    }

    return fileURL
}

// MARK: - Location + Weather

@MainActor
final class LocationWeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationText: String = ""
    @Published var weatherSummary: String = ""
    @Published var temperatureF: String = ""
    @Published var humidityPercent: String = ""
    @Published var windSpeedMPH: String = ""
    @Published var windDirectionText: String = ""
    @Published var barometricPressureInHg: String = ""
    @Published var dewPointF: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestLocationAndWeather() {
        errorMessage = nil
        isLoading = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Location access is denied. Enable it in Settings for this app."
        @unknown default:
            isLoading = false
            errorMessage = "Unable to access location."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Location access is denied. Enable it in Settings for this app."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        errorMessage = error.localizedDescription
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            isLoading = false
            errorMessage = "No location found."
            return
        }

        Task {
            async let geocodeTask: Void = reverseGeocode(location: location)
            async let weatherTask: Void = fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

            _ = await (geocodeTask, weatherTask)
            isLoading = false
        }
    }

    private func reverseGeocode(location: CLLocation) async {
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let place = placemarks.first {
                var parts: [String] = []

                if let name = place.name, !name.isEmpty { parts.append(name) }
                if let locality = place.locality, !locality.isEmpty { parts.append(locality) }
                if let administrativeArea = place.administrativeArea, !administrativeArea.isEmpty { parts.append(administrativeArea) }

                if parts.isEmpty {
                    locationText = "\(location.coordinate.latitude.clean), \(location.coordinate.longitude.clean)"
                } else {
                    locationText = parts.joined(separator: ", ")
                }
            } else {
                locationText = "\(location.coordinate.latitude.clean), \(location.coordinate.longitude.clean)"
            }
        } catch {
            locationText = "\(location.coordinate.latitude.clean), \(location.coordinate.longitude.clean)"
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async {
        do {
            var pointsRequest = URLRequest(url: URL(string: "https://api.weather.gov/points/\(latitude),\(longitude)")!)
            pointsRequest.setValue("AgTracker/1.0", forHTTPHeaderField: "User-Agent")

            let (pointsData, _) = try await URLSession.shared.data(for: pointsRequest)
            let points = try JSONDecoder().decode(NWSPointsResponse.self, from: pointsData)

            if let stationsURLString = points.properties?.observationStations,
               let stationsURL = URL(string: stationsURLString) {

                var stationsRequest = URLRequest(url: stationsURL)
                stationsRequest.setValue("AgTracker/1.0", forHTTPHeaderField: "User-Agent")

                let (stationsData, _) = try await URLSession.shared.data(for: stationsRequest)
                let stations = try JSONDecoder().decode(NWSStationsResponse.self, from: stationsData)

                if let firstStationURLString = stations.observationStations?.first,
                   let firstStationURL = URL(string: firstStationURLString + "/observations/latest") {

                    var latestRequest = URLRequest(url: firstStationURL)
                    latestRequest.setValue("AgTracker/1.0", forHTTPHeaderField: "User-Agent")

                    let (latestData, _) = try await URLSession.shared.data(for: latestRequest)
                    let latest = try JSONDecoder().decode(NWSLatestObservationResponse.self, from: latestData)

                    if let tempC = latest.properties?.temperature?.value {
                        temperatureF = celsiusToFahrenheit(tempC).clean
                    }

                    if let humidity = latest.properties?.relativeHumidity?.value {
                        humidityPercent = humidity.clean
                    }

                    if let windMps = latest.properties?.windSpeed?.value {
                        windSpeedMPH = metersPerSecondToMPH(windMps).clean
                    }

                    if let windDegrees = latest.properties?.windDirection?.value {
                        windDirectionText = degreesToCompass(windDegrees)
                    }

                    if let pressurePa = latest.properties?.barometricPressure?.value {
                        barometricPressureInHg = pascalToInHg(pressurePa).clean
                    }

                    if let dewC = latest.properties?.dewpoint?.value {
                        dewPointF = celsiusToFahrenheit(dewC).clean
                    }

                    var summaryParts: [String] = []
                    if let desc = latest.properties?.textDescription, !desc.isEmpty {
                        summaryParts.append(desc)
                    }
                    if !temperatureF.isEmpty {
                        summaryParts.append("\(temperatureF)°F")
                    }
                    if !humidityPercent.isEmpty {
                        summaryParts.append("RH \(humidityPercent)%")
                    }

                    weatherSummary = summaryParts.joined(separator: " | ")
                }
            }
        } catch {
            weatherSummary = "Weather unavailable"
        }
    }

    private func celsiusToFahrenheit(_ c: Double) -> Double {
        (c * 9.0 / 5.0) + 32.0
    }

    private func metersPerSecondToMPH(_ mps: Double) -> Double {
        mps * 2.23693629
    }

    private func pascalToInHg(_ pa: Double) -> Double {
        pa * 0.000295299830714
    }

    private func degreesToCompass(_ degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) & 15
        return directions[index]
    }
}

// MARK: - Weather.gov Models

struct NWSPointsResponse: Codable {
    let properties: NWSPointsProperties?
}

struct NWSPointsProperties: Codable {
    let observationStations: String?

    enum CodingKeys: String, CodingKey {
        case observationStations = "observationStations"
    }
}

struct NWSStationsResponse: Codable {
    let observationStations: [String]?

    enum CodingKeys: String, CodingKey {
        case observationStations = "observationStations"
    }
}

struct NWSLatestObservationResponse: Codable {
    let properties: NWSLatestObservationProperties?
}

struct NWSLatestObservationProperties: Codable {
    let textDescription: String?
    let temperature: NWSMeasurementValue?
    let dewpoint: NWSMeasurementValue?
    let relativeHumidity: NWSMeasurementValue?
    let windSpeed: NWSMeasurementValue?
    let windDirection: NWSMeasurementValue?
    let barometricPressure: NWSMeasurementValue?
}

struct NWSMeasurementValue: Codable {
    let value: Double?
}

// MARK: - App Entry

@main
struct AgTrackerSupabaseApp: App {
    @StateObject private var api = AgAPI()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
                .preferredColorScheme(.dark)
                .task {
                    await api.refreshAuthState()
                }
                .onOpenURL { url in
                    Task {
                        await api.handleAuthCallback(url)
                    }
                }
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var api: AgAPI

    var body: some View {
        Group {
            if api.isAuthed {
                MainView()
            } else {
                LoginView()
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Shared Styling

struct DarkRoundedCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}

struct PillButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .frame(minHeight: minHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
    }
}

struct RoundedTextFieldStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.white)
            .font(.system(size: 22, weight: .regular))
            .padding(.vertical, 10)
    }
}

extension View {
    func agTextFieldStyle() -> some View {
        modifier(RoundedTextFieldStyleModifier())
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var api: AgAPI

    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Spacer().frame(height: 90)

                Text("Ag Tracker")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)

                Text("Company Login")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))

                DarkRoundedCard {
                    VStack(spacing: 18) {
                        TextField("", text: $email, prompt: Text("Email").foregroundColor(.white.opacity(0.35)))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .agTextFieldStyle()

                        Divider().background(Color.white.opacity(0.14))

                        SecureField("", text: $password, prompt: Text("Password").foregroundColor(.white.opacity(0.35)))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .agTextFieldStyle()
                    }
                }

                DarkRoundedCard {
                    VStack(spacing: 0) {
                        Button {
                            Task {
                                isBusy = true
                                await api.signIn(email: email, password: password)
                                isBusy = false
                            }
                        } label: {
                            HStack {
                                if isBusy {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Sign In")
                                }
                                Spacer()
                            }
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white.opacity(0.90))
                            .padding(.vertical, 8)
                        }

                        Divider().background(Color.white.opacity(0.14))
                            .padding(.vertical, 10)

                        Button {
                            Task {
                                isBusy = true
                                await api.signUp(email: email, password: password)
                                isBusy = false
                            }
                        } label: {
                            HStack {
                                Text("Create Account")
                                Spacer()
                            }
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.vertical, 8)
                        }
                    }
                }

                if let error = api.errorMessage, !error.isEmpty {
                    DarkRoundedCard {
                        Text(error)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.red.opacity(0.95))
                    }
                }

                Text("First-time setup")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))

                DarkRoundedCard {
                    Text("""
If you see “No team membership found”, create a team and add your user to team_members in Supabase SQL.
After that, everyone added to the same team will share the same jobs.
""")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .lineSpacing(4)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Main View

struct MainView: View {
    @EnvironmentObject var api: AgAPI
    @State private var showingEditor = false
    @State private var pdfURL: URL?
    @State private var showingShare = false
    @State private var selectedJob: SprayJobRow?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button("Sign Out") {
                            Task { await api.signOut() }
                        }
                        .buttonStyle(PillButtonStyle())

                        Spacer()

                        HStack(spacing: 14) {
                            Button("Daily PDF") {
                                Task { await buildDailyPDF() }
                            }
                            .buttonStyle(PillButtonStyle())

                            Button {
                                showingEditor = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .medium))
                            }
                            .buttonStyle(PillButtonStyle())
                        }
                    }
                    .padding(.top, 6)

                    Text("Ag Tracker")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.white)

                    if api.isLoading {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView().tint(.white)
                            Spacer()
                        }
                        Spacer()
                    } else if api.jobs.isEmpty {
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(api.jobs) { job in
                                    Button {
                                        selectedJob = job
                                    } label: {
                                        JobRowCard(job: job)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) {
                                            Task { await api.deleteJob(job) }
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
            }
            .sheet(isPresented: $showingEditor) {
                JobEditorView()
                    .environmentObject(api)
            }
            .sheet(item: $selectedJob) { job in
                JobEditorView(existingJob: job)
                    .environmentObject(api)
            }
            .sheet(isPresented: $showingShare) {
                if let pdfURL {
                    ShareSheet(items: [pdfURL])
                }
            }
        }
    }

    private func buildDailyPDF() async {
        do {
            let today = Date()
            let calendar = Calendar.current

            let sameDayJobs = api.jobs.filter { job in
                guard let sprayDate = job.spray_date else { return false }
                let formatter = ISO8601DateFormatter()
                if let d = formatter.date(from: sprayDate) {
                    return calendar.isDate(d, inSameDayAs: today)
                }
                if let d2 = DateFormatter.shortDateOnly.date(from: sprayDate) {
                    return calendar.isDate(d2, inSameDayAs: today)
                }
                return false
            }

            let jobsToUse = sameDayJobs.isEmpty ? api.jobs : sameDayJobs

            var chemMap: [UUID: [ChemicalRow]] = [:]
            for job in jobsToUse {
                let chems = try await api.loadChemicals(jobID: job.id)
                chemMap[job.id] = chems
            }

            let url = try makeDailySummaryPDF(date: today, jobs: jobsToUse, chemsByJob: chemMap)
            pdfURL = url
            showingShare = true
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }
}

struct JobRowCard: View {
    let job: SprayJobRow

    var body: some View {
        DarkRoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(job.job_name ?? "Untitled Job")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                if let field = job.field_name, !field.isEmpty {
                    Text(field)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                }

                HStack(spacing: 14) {
                    Label("\(job.total_acres_sprayed.clean) ac", systemImage: "leaf")
                    if let temp = job.temperature_f {
                        Label("\(temp.clean)°F", systemImage: "thermometer")
                    }
                    if let wind = job.wind_speed_mph {
                        Label("\(wind.clean) mph", systemImage: "wind")
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.60))

                if let location = job.location_name, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.50))
                }
            }
        }
    }
}

// MARK: - Job Editor

struct JobEditorView: View {
    @EnvironmentObject var api: AgAPI
    @Environment(\.dismiss) private var dismiss

    let existingJob: SprayJobRow?

    @StateObject private var locationWeather = LocationWeatherManager()

    @State private var jobName = ""
    @State private var fieldName = ""
    @State private var farmName = ""
    @State private var crop = ""
    @State private var acres = ""

    @State private var tempF = ""
    @State private var humidityPercent = ""
    @State private var windSpeedMPH = ""
    @State private var windDirection = ""
    @State private var barometricPressureInHg = ""
    @State private var dewPointF = ""

    @State private var locationName = ""
    @State private var weatherSummary = ""
    @State private var notes = ""

    @State private var chemicalDrafts: [ChemicalDraft] = [ChemicalDraft()]
    @State private var saving = false

    init(existingJob: SprayJobRow? = nil) {
        self.existingJob = existingJob
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(existingJob == nil ? "New Job" : "Edit Job")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)

                        DarkRoundedCard {
                            VStack(spacing: 16) {
                                Button {
                                    locationWeather.requestLocationAndWeather()
                                } label: {
                                    HStack {
                                        if locationWeather.isLoading {
                                            ProgressView().tint(.white)
                                            Text("Loading Location & Weather...")
                                        } else {
                                            Image(systemName: "location.fill")
                                            Text("Use Current Location & Weather")
                                        }
                                        Spacer()
                                    }
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                divider
                                editorField("Job Name", text: $jobName)
                                divider
                                editorField("Field Name", text: $fieldName)
                                divider
                                editorField("Farm Name", text: $farmName)
                                divider
                                editorField("Crop", text: $crop)
                                divider
                                editorField("Total Acres Sprayed", text: $acres, keyboard: .decimalPad)
                                divider
                                editorField("Temperature °F", text: $tempF, keyboard: .decimalPad)
                                divider
                                editorField("Humidity %", text: $humidityPercent, keyboard: .decimalPad)
                                divider
                                editorField("Wind Speed mph", text: $windSpeedMPH, keyboard: .decimalPad)
                                divider
                                editorField("Wind Direction", text: $windDirection)
                                divider
                                editorField("Barometric Pressure inHg", text: $barometricPressureInHg, keyboard: .decimalPad)
                                divider
                                editorField("Dew Point °F", text: $dewPointF, keyboard: .decimalPad)
                                divider
                                editorField("Location", text: $locationName)
                                divider
                                editorField("Weather Summary", text: $weatherSummary)
                            }
                        }

                        DarkRoundedCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Notes")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))

                                TextEditor(text: $notes)
                                    .frame(minHeight: 120)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                            }
                        }

                        Text("Chemicals")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        ForEach($chemicalDrafts) { $draft in
                            DarkRoundedCard {
                                VStack(spacing: 14) {
                                    editorField("Chemical Name", text: $draft.chemical_name)
                                    divider
                                    editorField("Active Ingredient", text: $draft.active_ingredient)
                                    divider
                                    editorField("Rate Per Acre", text: bindingDoubleString($draft.rate_per_acre), keyboard: .decimalPad)
                                    divider

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Rate Unit")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.7))

                                        Picker("Rate Unit", selection: $draft.rate_unit) {
                                            ForEach(RateUnit.allCases) { unit in
                                                Text(unit.displayName).tag(unit)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    divider
                                    editorField("Acres Applied", text: bindingDoubleString($draft.acres_applied), keyboard: .decimalPad)
                                }
                            }
                        }

                        HStack {
                            Button("Add Chemical") {
                                if chemicalDrafts.count < 5 {
                                    chemicalDrafts.append(ChemicalDraft())
                                }
                            }
                            .buttonStyle(PillButtonStyle())

                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                dismiss()
                            }
                            .buttonStyle(PillButtonStyle())

                            Button {
                                Task {
                                    await saveJob()
                                }
                            } label: {
                                if saving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Save")
                                }
                            }
                            .buttonStyle(PillButtonStyle())
                        }

                        if existingJob != nil {
                            Button(role: .destructive) {
                                if let existingJob {
                                    Task {
                                        await api.deleteJob(existingJob)
                                        dismiss()
                                    }
                                }
                            } label: {
                                Text("Delete Job")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .fill(Color.red.opacity(0.10))
                                    )
                            }
                        }

                        if let error = api.errorMessage, !error.isEmpty {
                            DarkRoundedCard {
                                Text(error)
                                    .foregroundColor(.red.opacity(0.95))
                                    .font(.system(size: 17, weight: .medium))
                            }
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Ag Tracker")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
            .onChange(of: locationWeather.locationText) { _, newValue in
                if !newValue.isEmpty { locationName = newValue }
            }
            .onChange(of: locationWeather.weatherSummary) { _, newValue in
                if !newValue.isEmpty { weatherSummary = newValue }
            }
            .onChange(of: locationWeather.temperatureF) { _, newValue in
                if !newValue.isEmpty { tempF = newValue }
            }
            .onChange(of: locationWeather.humidityPercent) { _, newValue in
                if !newValue.isEmpty { humidityPercent = newValue }
            }
            .onChange(of: locationWeather.windSpeedMPH) { _, newValue in
                if !newValue.isEmpty { windSpeedMPH = newValue }
            }
            .onChange(of: locationWeather.windDirectionText) { _, newValue in
                if !newValue.isEmpty { windDirection = newValue }
            }
            .onChange(of: locationWeather.barometricPressureInHg) { _, newValue in
                if !newValue.isEmpty { barometricPressureInHg = newValue }
            }
            .onChange(of: locationWeather.dewPointF) { _, newValue in
                if !newValue.isEmpty { dewPointF = newValue }
            }
            .onChange(of: locationWeather.errorMessage) { _, newValue in
                if let newValue, !newValue.isEmpty {
                    api.errorMessage = newValue
                }
            }
            .task {
                await populateIfEditing()
            }
        }
    }

    private var divider: some View {
        Divider().background(Color.white.opacity(0.14))
    }

    private func editorField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            TextField("", text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .agTextFieldStyle()
        }
    }

    private func bindingDoubleString(_ value: Binding<Double>) -> Binding<String> {
        Binding<String>(
            get: { value.wrappedValue == 0 ? "" : value.wrappedValue.clean },
            set: { value.wrappedValue = Double($0) ?? 0 }
        )
    }

    private func saveJob() async {
        guard let teamID = api.teamID else {
            api.errorMessage = "No team membership found."
            return
        }

        saving = true
        defer { saving = false }

        do {
            let nowISO = ISO8601DateFormatter().string(from: Date())

            let job = SprayJobRow(
                id: existingJob?.id ?? UUID(),
                team_id: teamID,
                created_by: api.userID,
                job_name: jobName.nilIfEmpty,
                field_name: fieldName.nilIfEmpty,
                farm_name: farmName.nilIfEmpty,
                crop: crop.nilIfEmpty,
                total_acres_sprayed: Double(acres) ?? 0,
                spray_date: existingJob?.spray_date ?? nowISO,
                notes: notes.nilIfEmpty,
                is_closed: false,
                temperature_f: Double(tempF),
                humidity_percent: Double(humidityPercent),
                wind_speed_mph: Double(windSpeedMPH),
                wind_direction: windDirection.nilIfEmpty,
                barometric_pressure_inhg: Double(barometricPressureInHg),
                dew_point_f: Double(dewPointF),
                location_name: locationName.nilIfEmpty,
                weather_summary: weatherSummary.nilIfEmpty,
                created_at: existingJob?.created_at ?? nowISO
            )

            try await api.upsertJob(job)
            try await api.replaceChemicals(jobID: job.id, drafts: chemicalDrafts)
            dismiss()
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }

    private func populateIfEditing() async {
        guard let job = existingJob else { return }

        jobName = job.job_name ?? ""
        fieldName = job.field_name ?? ""
        farmName = job.farm_name ?? ""
        crop = job.crop ?? ""
        acres = job.total_acres_sprayed == 0 ? "" : job.total_acres_sprayed.clean

        tempF = job.temperature_f.cleanOrBlank
        humidityPercent = job.humidity_percent.cleanOrBlank
        windSpeedMPH = job.wind_speed_mph.cleanOrBlank
        windDirection = job.wind_direction ?? ""
        barometricPressureInHg = job.barometric_pressure_inhg.cleanOrBlank
        dewPointF = job.dew_point_f.cleanOrBlank

        locationName = job.location_name ?? ""
        weatherSummary = job.weather_summary ?? ""
        notes = job.notes ?? ""

        do {
            let rows = try await api.loadChemicals(jobID: job.id)
            if rows.isEmpty {
                chemicalDrafts = [ChemicalDraft()]
            } else {
                chemicalDrafts = rows.map {
                    ChemicalDraft(
                        chemical_name: $0.chemical_name ?? "",
                        active_ingredient: $0.active_ingredient ?? "",
                        rate_per_acre: $0.rate_per_acre,
                        rate_unit: RateUnit(rawValue: $0.rate_unit) ?? .oz_ac,
                        acres_applied: $0.acres_applied
                    )
                }
            }
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
