import SwiftUI
import UIKit
import Combine
import Foundation
import CoreLocation
import Supabase

// MARK: - Supabase Config

private let supabaseURL = URL(string: "https://rocobuoemdaevzgdzpnv.supabase.co")!
private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJvY29idW9lbWRhZXZ6Z2R6cG52Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE2MjQ4NzcsImV4cCI6MjA4NzIwMDg3N30.oK7eCKo8bNK2ovXsZLM5V30KzlSp_E1-q5xjNhz0pfI"

// MARK: - App Entry

@main
struct AgSprayDroneApp: App {
    @StateObject private var api = AgAPI()

    var body: some Scene {
        WindowGroup {
            SprayJobManagementView()
                .environmentObject(api)
        }
    }
}

// MARK: - Management Screen

struct SprayJobManagementView: View {
    @EnvironmentObject var api: AgAPI

    @State private var showNewJob = false
    @State private var editingJob: SprayJobRow?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerSection

                    if api.isLoading && api.jobs.isEmpty {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    } else if api.jobs.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(api.jobs) { job in
                                Button {
                                    editingJob = job
                                } label: {
                                    jobRow(job)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.black)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.black)
                        .refreshable {
                            await api.loadJobs()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showNewJob) {
                JobEditorView()
                    .environmentObject(api)
            }
            .sheet(item: $editingJob) { job in
                JobEditorView(existingJob: job)
                    .environmentObject(api)
            }
            .task {
                await api.bootstrap()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spray Job Manager")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    Text("Track fields, weather, chemicals, and acreage")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()
            }

            HStack(spacing: 12) {
                dashboardCard(title: "Total Jobs", value: "\(api.jobs.count)")
                dashboardCard(title: "Open Jobs", value: "\(api.jobs.filter { !$0.is_closed }.count)")
                dashboardCard(title: "Acres", value: api.jobs.reduce(0) { $0 + $1.total_acres_sprayed }.clean)
            }

            Button {
                showNewJob = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Spray Job")
                    Spacer()
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.blue.opacity(0.9))
                )
            }
            .buttonStyle(.plain)

            if let error = api.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red.opacity(0.95))
            }
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "leaf.circle")
                .font(.system(size: 60))
                .foregroundColor(.green.opacity(0.85))

            Text("No spray jobs yet")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("Create your first spray job to start tracking fields, weather, and chemical use.")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Button {
                showNewJob = true
            } label: {
                Text("Create First Job")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.blue.opacity(0.9))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func dashboardCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func jobRow(_ job: SprayJobRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(job.field_name ?? "Unnamed Field")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Text(job.is_closed ? "Closed" : "Open")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(job.is_closed ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill((job.is_closed ? Color.green : Color.orange).opacity(0.18))
                    )
            }

            if let farm = job.farm_name, !farm.isEmpty {
                Text("Farm: \(farm)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.75))
            }

            HStack(spacing: 16) {
                Label("\(job.total_acres_sprayed.clean) ac", systemImage: "map")
                    .foregroundColor(.white.opacity(0.8))

                if let temp = job.temperature_f {
                    Label("\(temp.clean)°F", systemImage: "thermometer")
                        .foregroundColor(.white.opacity(0.8))
                }

                if let wind = job.wind_speed_mph {
                    Label("\(wind.clean) mph", systemImage: "wind")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .font(.system(size: 13, weight: .medium))

            if let location = job.location_name, !location.isEmpty {
                Text(location)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Job Editor

struct JobEditorView: View {
    @EnvironmentObject var api: AgAPI
    @Environment(\.dismiss) private var dismiss

    let existingJob: SprayJobRow?

    @StateObject private var locationWeather = LocationWeatherManager()

    @State private var growerName = ""
    @State private var farmOwnerName = ""
    @State private var addressLine = ""
    @State private var city = ""
    @State private var stateRegion = ""
    @State private var zipCode = ""
    @State private var phone = ""
    @State private var contactEmail = ""

    @State private var jobName = ""
    @State private var fieldName = ""
    @State private var farmName = ""
    @State private var crop = ""
    @State private var acres = ""

    @State private var startDate = Date()
    @State private var endDate = Date()

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
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(existingJob == nil ? "New Spray Job" : "Edit Spray Job")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)

                        DarkRoundedCard {
                            VStack(spacing: 16) {
                                editorField("Job Name", text: $jobName)
                                divider
                                editorField("Field Name / ID", text: $fieldName)
                                divider
                                editorField("Farm Name", text: $farmName)
                                divider
                                editorField("Crop", text: $crop)
                                divider
                                editorField("Grower Name", text: $growerName)
                                divider
                                editorField("Farm Owner Name", text: $farmOwnerName)
                                divider
                                editorField("Address Line", text: $addressLine)
                                divider
                                editorField("City", text: $city)
                                divider
                                editorField("State", text: $stateRegion)
                                divider
                                editorField("ZIP", text: $zipCode)
                                divider
                                editorField("Phone", text: $phone, keyboard: .phonePad)
                                divider
                                editorField("Email", text: $contactEmail, keyboard: .emailAddress)
                            }
                        }

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
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                divider
                                editorField("Location", text: $locationName)
                                divider
                                editorField("Weather Summary", text: $weatherSummary)
                            }
                        }

                        DarkRoundedCard {
                            VStack(spacing: 16) {
                                editorField("Total Acres Sprayed", text: $acres, keyboard: .decimalPad)
                                divider

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Start")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.7))
                                    DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }

                                divider

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("End")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.7))
                                    DatePicker("", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }
                            }
                        }

                        DarkRoundedCard {
                            VStack(spacing: 16) {
                                editorField("Wind Speed mph", text: $windSpeedMPH, keyboard: .decimalPad)
                                divider
                                editorField("Wind Direction", text: $windDirection)
                                divider
                                editorField("Humidity %", text: $humidityPercent, keyboard: .decimalPad)
                                divider
                                editorField("Dew Point °F", text: $dewPointF, keyboard: .decimalPad)
                                divider
                                editorField("Barometric Pressure inHg", text: $barometricPressureInHg, keyboard: .decimalPad)
                                divider
                                editorField("Temperature °F", text: $tempF, keyboard: .decimalPad)
                            }
                        }

                        DarkRoundedCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Notes")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))

                                TextEditor(text: $notes)
                                    .frame(minHeight: 120)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            }
                        }

                        Text("Chemicals (up to 5)")
                            .font(.system(size: 22, weight: .bold))
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
                                            .font(.system(size: 15, weight: .semibold))
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

                                    Text(chemicalTotalText(draft))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
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

                        if existingJob != nil {
                            Button(role: .destructive) {
                                guard let existingJob else { return }
                                Task { @MainActor in
                                    await api.deleteJob(existingJob)
                                    dismiss()
                                }
                            } label: {
                                Text("Delete Job")
                                    .font(.system(size: 17, weight: .medium))
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
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(24)
                }
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
        .onChange(of: locationWeather.addressStreet) { _, newValue in
            if !newValue.isEmpty { addressLine = newValue }
        }
        .onChange(of: locationWeather.addressCity) { _, newValue in
            if !newValue.isEmpty { city = newValue }
        }
        .onChange(of: locationWeather.addressState) { _, newValue in
            if !newValue.isEmpty { stateRegion = newValue }
        }
        .onChange(of: locationWeather.addressZIP) { _, newValue in
            if !newValue.isEmpty { zipCode = newValue }
        }
        .task {
            await populateIfEditing()
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.white)

            Spacer()

            Text(existingJob == nil ? "New Spray Job" : "Edit Spray Job")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            Button {
                Task { @MainActor in
                    await saveJob()
                }
            } label: {
                if saving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save")
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .disabled(saving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.95))
    }

    private var divider: some View {
        Divider().background(Color.white.opacity(0.14))
    }

    private func editorField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
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

    private func chemicalTotalText(_ draft: ChemicalDraft) -> String {
        let total = max(0, draft.rate_per_acre) * max(0, draft.acres_applied)
        switch draft.rate_unit {
        case .gal_ac: return "Total \(total.clean) gal"
        case .oz_ac: return "Total \(total.clean) oz"
        case .pt_ac: return "Total \(total.clean) pt"
        case .qt_ac: return "Total \(total.clean) qt"
        case .lb_ac: return "Total \(total.clean) lb"
        }
    }

    @MainActor
    private func saveJob() async {
        guard let teamID = api.teamID else {
            api.errorMessage = "No team membership found. Log in first or confirm team_members has a row for this user."
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
                is_closed: existingJob?.is_closed ?? false,
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
            await api.loadJobs()
            dismiss()
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }

    @MainActor
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
            chemicalDrafts = rows.isEmpty ? [ChemicalDraft()] : rows.map {
                ChemicalDraft(
                    chemical_name: $0.chemical_name ?? "",
                    active_ingredient: $0.active_ingredient ?? "",
                    rate_per_acre: $0.rate_per_acre,
                    rate_unit: RateUnit(rawValue: $0.rate_unit) ?? .oz_ac,
                    acres_applied: $0.acres_applied
                )
            }
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Supabase API

@MainActor
final class AgAPI: ObservableObject {
    let client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseAnonKey)

    @Published var jobs: [SprayJobRow] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var isAuthed = false
    @Published var userID: UUID?
    @Published var teamID: UUID?
    @Published var teamRole: String?

    func bootstrap() async {
        await refreshAuthState()
        await loadJobs()
    }

    func refreshAuthState() async {
        errorMessage = nil

        do {
            let session = try await client.auth.session
            isAuthed = true
            userID = session.user.id

            do {
                let membership: TeamMemberRow = try await client
                    .from("team_members")
                    .select()
                    .eq("user_id", value: session.user.id.uuidString)
                    .single()
                    .execute()
                    .value

                teamID = membership.team_id
                teamRole = membership.role
            } catch {
                teamID = nil
                teamRole = nil
                errorMessage = "Signed in, but no team_members row was found for this user."
            }
        } catch {
            isAuthed = false
            userID = nil
            teamID = nil
            teamRole = nil
        }
    }

    func loadJobs() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let teamID {
                let rows: [SprayJobRow] = try await client
                    .from("spray_jobs")
                    .select()
                    .eq("team_id", value: teamID.uuidString)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                jobs = rows
            } else {
                jobs = []
            }
        } catch {
            errorMessage = "Load jobs failed: \(error.localizedDescription)"
        }
    }

    func upsertJob(_ job: SprayJobRow) async throws {
        try await client
            .from("spray_jobs")
            .upsert(job)
            .execute()
    }

    func replaceChemicals(jobID: UUID, drafts: [ChemicalDraft]) async throws {
        try await client
            .from("chemical_entries")
            .delete()
            .eq("job_id", value: jobID.uuidString)
            .execute()

        let filtered = drafts.filter {
            !$0.chemical_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.active_ingredient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.rate_per_acre > 0 ||
            $0.acres_applied > 0
        }

        guard !filtered.isEmpty else { return }

        let payload = filtered.map {
            ChemicalRow(
                id: UUID(),
                job_id: jobID,
                chemical_name: $0.chemical_name.nilIfEmpty,
                active_ingredient: $0.active_ingredient.nilIfEmpty,
                rate_per_acre: $0.rate_per_acre,
                rate_unit: $0.rate_unit.rawValue,
                acres_applied: $0.acres_applied
            )
        }

        try await client
            .from("chemical_entries")
            .insert(payload)
            .execute()
    }

    func deleteJob(_ job: SprayJobRow) async {
        do {
            try await client
                .from("chemical_entries")
                .delete()
                .eq("job_id", value: job.id.uuidString)
                .execute()

            try await client
                .from("spray_jobs")
                .delete()
                .eq("id", value: job.id.uuidString)
                .execute()

            await loadJobs()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func loadChemicals(jobID: UUID) async throws -> [ChemicalRow] {
        try await client
            .from("chemical_entries")
            .select()
            .eq("job_id", value: jobID.uuidString)
            .execute()
            .value
    }
}

// MARK: - Models

struct TeamMemberRow: Codable, Sendable {
    var team_id: UUID
    var user_id: UUID
    var role: String?
}

struct SprayJobRow: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var team_id: UUID
    var created_by: UUID?
    var job_name: String?
    var field_name: String?
    var farm_name: String?
    var crop: String?
    var total_acres_sprayed: Double
    var spray_date: String
    var notes: String?
    var is_closed: Bool
    var temperature_f: Double?
    var humidity_percent: Double?
    var wind_speed_mph: Double?
    var wind_direction: String?
    var barometric_pressure_inhg: Double?
    var dew_point_f: Double?
    var location_name: String?
    var weather_summary: String?
    var created_at: String
}

struct ChemicalRow: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var job_id: UUID
    var chemical_name: String?
    var active_ingredient: String?
    var rate_per_acre: Double = 0
    var rate_unit: String = RateUnit.oz_ac.rawValue
    var acres_applied: Double = 0
}

enum RateUnit: String, CaseIterable, Identifiable, Sendable {
    case gal_ac
    case oz_ac
    case pt_ac
    case qt_ac
    case lb_ac

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

struct ChemicalDraft: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var chemical_name: String = ""
    var active_ingredient: String = ""
    var rate_per_acre: Double = 0
    var rate_unit: RateUnit = .oz_ac
    var acres_applied: Double = 0
}

// MARK: - Real GPS + Weather

@MainActor
final class LocationWeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLoading = false
    @Published var locationText = ""
    @Published var weatherSummary = ""
    @Published var temperatureF = ""
    @Published var humidityPercent = ""
    @Published var windSpeedMPH = ""
    @Published var windDirectionText = ""
    @Published var barometricPressureInHg = ""
    @Published var dewPointF = ""

    @Published var errorMessage: String?

    @Published var addressStreet = ""
    @Published var addressCity = ""
    @Published var addressState = ""
    @Published var addressZIP = ""

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestLocationAndWeather() {
        errorMessage = nil

        guard CLLocationManager.locationServicesEnabled() else {
            errorMessage = "Location Services are turned off."
            return
        }

        isLoading = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            isLoading = false
            errorMessage = "Location permission is denied or restricted."
        @unknown default:
            isLoading = false
            errorMessage = "Unknown location authorization state."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            isLoading = false
            errorMessage = "Location permission is denied or restricted."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        errorMessage = "Location failed: \(error.localizedDescription)"
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            isLoading = false
            errorMessage = "No location returned."
            return
        }

        Task {
            do {
                try await reverseGeocode(location)
                try await fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { return }

        addressStreet = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        addressCity = placemark.locality ?? ""
        addressState = placemark.administrativeArea ?? ""
        addressZIP = placemark.postalCode ?? ""

        let pretty = [placemark.name, placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        locationText = pretty.isEmpty
            ? "\(location.coordinate.latitude.clean), \(location.coordinate.longitude.clean)"
            : pretty
    }

    private func fetchWeather(latitude: Double, longitude: Double) async throws {
        let lat = String(format: "%.6f", latitude)
        let lon = String(format: "%.6f", longitude)

        let urlString =
            "https://api.open-meteo.com/v1/forecast" +
            "?latitude=\(lat)" +
            "&longitude=\(lon)" +
            "&current=temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,pressure_msl,dew_point_2m,weather_code" +
            "&temperature_unit=fahrenheit" +
            "&wind_speed_unit=mph"

        guard let url = URL(string: urlString) else {
            throw WeatherError.badURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        temperatureF = decoded.current.temperature_2m.clean
        humidityPercent = decoded.current.relative_humidity_2m.clean
        windSpeedMPH = decoded.current.wind_speed_10m.clean
        windDirectionText = Self.degreesToCompass(decoded.current.wind_direction_10m)
        dewPointF = decoded.current.dew_point_2m.clean

        let inHg = decoded.current.pressure_msl * 0.0295299830714
        barometricPressureInHg = String(format: "%.2f", inHg)

        weatherSummary = Self.weatherCodeDescription(decoded.current.weather_code)
    }

    private static func degreesToCompass(_ degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) & 15
        return directions[index]
    }

    private static func weatherCodeDescription(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2, 3: return "Partly Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm / Hail"
        default: return "Unknown"
        }
    }

    enum WeatherError: LocalizedError {
        case badURL

        var errorDescription: String? {
            switch self {
            case .badURL: return "Weather URL could not be created."
            }
        }
    }
}

struct OpenMeteoResponse: Codable {
    struct Current: Codable {
        let temperature_2m: Double
        let relative_humidity_2m: Double
        let wind_speed_10m: Double
        let wind_direction_10m: Double
        let pressure_msl: Double
        let dew_point_2m: Double
        let weather_code: Int
    }

    let current: Current
}

// MARK: - Styling

struct DarkRoundedCard<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.blue.opacity(configuration.isPressed ? 0.7 : 0.9))
            )
    }
}

extension View {
    func agTextFieldStyle() -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .foregroundColor(.white)
    }
}

// MARK: - Helpers

private extension Optional where Wrapped == Double {
    var cleanOrBlank: String {
        switch self {
        case .some(let value):
            return value == 0 ? "" : value.clean
        case .none:
            return ""
        }
    }
}

private extension Double {
    var clean: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
