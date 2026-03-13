import SwiftUI
import UIKit
import Combine
import Foundation

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

                    if api.jobs.isEmpty {
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

    let job = SprayJobRow(
        id: existingJob?.id ?? UUID(),
        team_id: teamID,
        created_at: existingJob?.created_at ?? nowISO,
        date: existingJob?.date ?? nowISO,
        field_name: fieldName.nilIfEmpty,
        crop: crop.nilIfEmpty,
        notes: notes.nilIfEmpty,
        total_acres_sprayed: Double(acres) ?? 0,
        created_by: api.userID,

        grower_name: growerName.nilIfEmpty,
        farm_owner_name: farmOwnerName.nilIfEmpty,
        address_line: addressLine.nilIfEmpty,
        city: city.nilIfEmpty,
        state: stateRegion.nilIfEmpty,
        zip: zipCode.nilIfEmpty,
        phone: phone.nilIfEmpty,
        email: contactEmail.nilIfEmpty,

        latitude: nil,
        longitude: nil,

        weather_summary: weatherSummary.nilIfEmpty,
        start_time: ISO8601DateFormatter().string(from: startDate),
        end_time: ISO8601DateFormatter().string(from: endDate),

        wind_speed_mph: Double(windSpeedMPH),
        wind_direction: windDirection.nilIfEmpty,
        humidity_percent: Double(humidityPercent),
        dew_point_f: Double(dewPointF),
        pressure_inhg: Double(barometricPressureInHg),
        temperature_f: Double(tempF)
    )

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

// MARK: - In-Memory API

@MainActor
final class AgAPI: ObservableObject {
    @Published var errorMessage: String? = nil
    @Published var jobs: [SprayJobRow] = [
        SprayJobRow(
            id: UUID(),
            team_id: UUID(),
            created_by: UUID(),
            job_name: "North 40",
            field_name: "North Field",
            farm_name: "Hetsler Farm",
            crop: "Corn",
            total_acres_sprayed: 42,
            spray_date: ISO8601DateFormatter().string(from: Date()),
            notes: "Fungicide pass completed",
            is_closed: false,
            temperature_f: 72,
            humidity_percent: 44,
            wind_speed_mph: 6,
            wind_direction: "NE",
            barometric_pressure_inhg: 29.94,
            dew_point_f: 48,
            location_name: "North Farm Block",
            weather_summary: "Clear",
            created_at: ISO8601DateFormatter().string(from: Date())
        ),
        SprayJobRow(
            id: UUID(),
            team_id: UUID(),
            created_by: UUID(),
            job_name: "South Beans",
            field_name: "South Bean Field",
            farm_name: "River Bend Acres",
            crop: "Soybeans",
            total_acres_sprayed: 87.5,
            spray_date: ISO8601DateFormatter().string(from: Date()),
            notes: "Herbicide application",
            is_closed: false,
            temperature_f: 68,
            humidity_percent: 52,
            wind_speed_mph: 4,
            wind_direction: "W",
            barometric_pressure_inhg: 30.02,
            dew_point_f: 50,
            location_name: "South Parcel",
            weather_summary: "Partly Cloudy",
            created_at: ISO8601DateFormatter().string(from: Date())
        )
    ]

    private var chemicalStore: [UUID: [ChemicalRow]] = [:]

    var teamID: UUID? = UUID()
    var userID: UUID? = UUID()

    func upsertJob(_ job: SprayJobRow) async throws {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
    }

    func replaceChemicals(jobID: UUID, drafts: [ChemicalDraft]) async throws {
        chemicalStore[jobID] = drafts.map {
            ChemicalRow(
                chemical_name: $0.chemical_name.nilIfEmpty,
                active_ingredient: $0.active_ingredient.nilIfEmpty,
                rate_per_acre: $0.rate_per_acre,
                rate_unit: $0.rate_unit.rawValue,
                acres_applied: $0.acres_applied
            )
        }
    }

    func deleteJob(_ job: SprayJobRow) async {
        jobs.removeAll { $0.id == job.id }
        chemicalStore[job.id] = nil
    }

    func loadChemicals(jobID: UUID) async throws -> [ChemicalRow] {
        chemicalStore[jobID] ?? []
    }
}

// MARK: - Models

struct SprayJobRow: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var team_id: UUID
    var created_at: String
    var date: String?
    var field_name: String?
    var crop: String?
    var notes: String?
    var total_acres_sprayed: Double
    var created_by: UUID?

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
    var start_time: String?
    var end_time: String?

    var wind_speed_mph: Double?
    var wind_direction: String?
    var humidity_percent: Double?
    var dew_point_f: Double?
    var pressure_inhg: Double?
    var temperature_f: Double?
}

struct ChemicalRow: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
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

// MARK: - Mock Location / Weather

@MainActor
final class LocationWeatherManager: ObservableObject {
    @Published var isLoading = false
    @Published var locationText = ""
    @Published var weatherSummary = ""
    @Published var temperatureF = ""
    @Published var humidityPercent = ""
    @Published var windSpeedMPH = ""
    @Published var windDirectionText = ""
    @Published var barometricPressureInHg = ""
    @Published var dewPointF = ""

    @Published var errorMessage: String? = nil

    @Published var addressStreet = ""
    @Published var addressCity = ""
    @Published var addressState = ""
    @Published var addressZIP = ""

    func requestLocationAndWeather() {
        isLoading = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.isLoading = false
            self.locationText = "Current Location"
            self.weatherSummary = "Clear"
            self.temperatureF = "72"
            self.humidityPercent = "40"
            self.windSpeedMPH = "5"
            self.windDirectionText = "NE"
            self.barometricPressureInHg = "29.92"
            self.dewPointF = "46"
            self.addressStreet = "123 Main St"
            self.addressCity = "Springfield"
            self.addressState = "IL"
            self.addressZIP = "62701"
        }
    }
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
