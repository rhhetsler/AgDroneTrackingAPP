import SwiftUI
import UIKit
import Foundation
import CoreLocation
import Combine
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
            RootView()
                .environmentObject(api)
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var api: AgAPI

    var body: some View {
        Group {
            if api.isBootstrapping {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView("Loading...")
                        .tint(.white)
                        .foregroundColor(.white)
                }
            } else if api.isAuthed {
                SprayJobManagementView()
            } else {
                AuthView()
            }
        }
        .task {
            await api.bootstrap()
        }
    }
}

// MARK: - Auth View

struct AuthView: View {
    @EnvironmentObject var api: AgAPI

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Spacer(minLength: 40)

                        Text("Ag Spray Drone")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)

                        Text("Sign in to access spray jobs, weather, chemicals, acreage, GPS, and daily PDF reports")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.72))

                        DarkRoundedCard {
                            VStack(spacing: 16) {
                                editorField("Email", text: $email, keyboard: .emailAddress, capitalization: .never)

                                Divider().background(Color.white.opacity(0.14))

                                SecureField("", text: $password, prompt: Text("Password").foregroundColor(.white.opacity(0.35)))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .agTextFieldStyle()
                            }
                        }

                        Button {
                            Task { @MainActor in
                                await performAuth()
                            }
                        } label: {
                            HStack {
                                if isBusy {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: isSignUp ? "person.crop.circle.badge.plus" : "person.crop.circle.badge.checkmark")
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                }
                                Spacer()
                            }
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.blue.opacity(0.92))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)

                        Button {
                            isSignUp.toggle()
                            api.errorMessage = nil
                        } label: {
                            Text(isSignUp ? "Already have an account? Sign in" : "Need an account? Create one")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.78))
                        }
                        .buttonStyle(.plain)

                        DarkRoundedCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Important")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)

                                Text("After creating an account, that user still needs a matching row in team_members before jobs will load")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.74))
                            }
                        }

                        if let error = api.errorMessage, !error.isEmpty {
                            DarkRoundedCard {
                                Text(error)
                                    .foregroundColor(.red.opacity(0.96))
                                    .font(.system(size: 15, weight: .medium))
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    @MainActor
    private func performAuth() async {
        api.errorMessage = nil

        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            api.errorMessage = "Enter your email address."
            return
        }

        guard password.count >= 6 else {
            api.errorMessage = "Password must be at least 6 characters."
            return
        }

        isBusy = true
        defer { isBusy = false }

        if isSignUp {
            await api.signUp(email: email, password: password)
        } else {
            await api.signIn(email: email, password: password)
        }
    }

    private func editorField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))

            TextField("", text: text, prompt: Text(title).foregroundColor(.white.opacity(0.35)))
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .agTextFieldStyle()
        }
    }
}

// MARK: - Management

enum ManagementTab: String, CaseIterable, Identifiable {
    case jobs = "Spray Jobs"
    case reports = "Daily Reports"

    var id: String { rawValue }
}

struct SprayJobManagementView: View {
    @EnvironmentObject var api: AgAPI

    @State private var selectedTab: ManagementTab = .jobs
    @State private var showNewJob = false
    @State private var editingJob: SprayJobRow?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerSection

                    Picker("Section", selection: $selectedTab) {
                        ForEach(ManagementTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                    .colorScheme(.dark)

                    switch selectedTab {
                    case .jobs:
                        jobsContent
                    case .reports:
                        DailyReportsView()
                            .environmentObject(api)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showNewJob) {
                JobEditorView(existingJob: nil)
                    .environmentObject(api)
            }
            .sheet(item: $editingJob) { job in
                JobEditorView(existingJob: job)
                    .environmentObject(api)
            }
        }
    }

    @ViewBuilder
    private var jobsContent: some View {
        if api.isLoading && api.jobs.isEmpty {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        } else if !api.hasTeamMembership {
            noTeamState
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spray Job Manager")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    Text("Track fields, weather, chemicals, acreage, GPS, and daily PDF reports")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                }

                Spacer()

                Button {
                    Task { @MainActor in
                        await api.signOut()
                    }
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                dashboardCard(title: "Total Jobs", value: "\(api.jobs.count)")
                dashboardCard(title: "Saved Jobs", value: "\(api.jobs.count)")
                dashboardCard(title: "Acres", value: api.jobs.reduce(0) { $0 + $1.total_acres_sprayed }.clean)
            }

            if selectedTab == .jobs {
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
                            .fill(Color.blue.opacity(0.90))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!api.hasTeamMembership)
                .opacity(api.hasTeamMembership ? 1 : 0.45)
            }

            if let error = api.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red.opacity(0.95))
            }
        }
        .padding(20)
    }

    private var noTeamState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.9))

            Text("No team membership found")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("This user is signed in, but there is no matching row in team_members yet. Add the user to a team in Supabase, then tap reload.")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                Task { @MainActor in
                    await api.bootstrap()
                }
            } label: {
                Text("Reload Team Access")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.blue.opacity(0.90))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
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

            Text("Create your first spray job to start tracking fields, weather, and chemical use")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.72))
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
                            .fill(Color.blue.opacity(0.90))
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
                .foregroundColor(.white.opacity(0.72))

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

                Text("Saved")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
            }

            if let grower = job.grower_name, !grower.isEmpty {
                Text("Grower: \(grower)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.75))
            }

            HStack(spacing: 16) {
                Label("\(job.total_acres_sprayed.clean) ac", systemImage: "map")
                    .foregroundColor(.white.opacity(0.82))

                if let temp = job.temperature_f {
                    Label("\(temp.clean)°F", systemImage: "thermometer")
                        .foregroundColor(.white.opacity(0.82))
                }

                if let wind = job.wind_speed_mph {
                    Label("\(wind.clean) mph", systemImage: "wind")
                        .foregroundColor(.white.opacity(0.82))
                }
            }
            .font(.system(size: 13, weight: .medium))

            if let address = job.address_line, !address.isEmpty {
                Text(address)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.66))
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Daily Reports

struct DailyReportsView: View {
    @EnvironmentObject var api: AgAPI

    @State private var selectedDate = Date()
    @State private var reportJobs: [SprayJobRow] = []
    @State private var reportChemicals: [UUID: [ChemicalRow]] = [:]
    @State private var isLoading = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DarkRoundedCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Daily PDF Report")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        DatePicker("Report Date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)

                        Button {
                            Task { @MainActor in
                                await loadReportData()
                            }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Load Daily Report")
                                }
                                Spacer()
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.blue.opacity(0.90))
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { @MainActor in
                                await createAndSharePDF()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.richtext")
                                Text("Create PDF Report")
                                Spacer()
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.green.opacity(0.80))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(reportJobs.isEmpty)
                        .opacity(reportJobs.isEmpty ? 0.45 : 1)
                    }
                }

                HStack(spacing: 12) {
                    summaryCard(title: "Jobs", value: "\(reportJobs.count)")
                    summaryCard(title: "Acres", value: totalDailyAcres.clean)
                    summaryCard(title: "Chemicals", value: "\(totalChemicalLines)")
                }

                if reportJobs.isEmpty {
                    DarkRoundedCard {
                        Text("No jobs found for the selected date. Load a day with spray activity to create a PDF report.")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.72))
                    }
                } else {
                    ForEach(reportJobs) { job in
                        DarkRoundedCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(job.field_name ?? "Unnamed Field")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)

                                if let grower = job.grower_name, !grower.isEmpty {
                                    Text("Grower: \(grower)")
                                        .foregroundColor(.white.opacity(0.78))
                                }

                                Text("Acres: \(job.total_acres_sprayed.clean)")
                                    .foregroundColor(.white.opacity(0.78))

                                if let weather = job.weather_summary, !weather.isEmpty {
                                    Text("Weather: \(weather)")
                                        .foregroundColor(.white.opacity(0.78))
                                }

                                if let chemicals = reportChemicals[job.id], !chemicals.isEmpty {
                                    Divider().background(Color.white.opacity(0.14))
                                    Text("Chemicals")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)

                                    ForEach(chemicals) { chemical in
                                        Text(chemical.descriptionLine)
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.72))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .task {
            await loadReportData()
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }

    private var totalDailyAcres: Double {
        reportJobs.reduce(0) { $0 + $1.total_acres_sprayed }
    }

    private var totalChemicalLines: Int {
        reportChemicals.values.reduce(0) { $0 + $1.count }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    @MainActor
    private func loadReportData() async {
        guard let teamID = api.teamID else {
            api.errorMessage = "No team membership found."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let jobs = try await api.loadJobsForDate(selectedDate, teamID: teamID)
            reportJobs = jobs

            var mapped: [UUID: [ChemicalRow]] = [:]
            for job in jobs {
                mapped[job.id] = try await api.loadChemicals(jobID: job.id)
            }
            reportChemicals = mapped
            api.errorMessage = nil
        } catch {
            api.errorMessage = "Daily report load failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func createAndSharePDF() async {
        guard !reportJobs.isEmpty else { return }

        do {
            let url = try DailyReportPDFBuilder.build(
                date: selectedDate,
                jobs: reportJobs,
                chemicalsByJob: reportChemicals
            )
            shareURL = url
            showShareSheet = true
        } catch {
            api.errorMessage = "PDF creation failed: \(error.localizedDescription)"
        }
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

    @State private var fieldName = ""
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
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""
    @State private var gpsCoordinatesText = ""
    @State private var notes = ""

    @State private var chemicalDrafts: [ChemicalDraft] = [ChemicalDraft()]
    @State private var saving = false

    #if targetEnvironment(simulator)
    private let simulatorLocationHint = "Simulator tip: choose Features > Location in the iPhone Simulator and pick a test location before using GPS."
    #else
    private let simulatorLocationHint = ""
    #endif

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
                                editorField("Field Name / ID", text: $fieldName)
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
                                editorField("Email", text: $contactEmail, keyboard: .emailAddress, capitalization: .never)
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
                                            Text("Loading Live GPS & Weather...")
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

                                if !simulatorLocationHint.isEmpty {
                                    divider
                                    Text(simulatorLocationHint)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.72))
                                }

                                if let timestamp = locationWeather.lastUpdateText {
                                    divider
                                    Text("Last live update: \(timestamp)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.green.opacity(0.9))
                                }

                                if !gpsCoordinatesText.isEmpty {
                                    divider
                                    Text("Current Coordinates: \(gpsCoordinatesText)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.82))
                                }

                                divider
                                editorField("Location", text: $locationName)

                                divider
                                editorField("Manual Latitude", text: $manualLatitude, keyboard: .decimalPad, capitalization: .never)

                                divider
                                editorField("Manual Longitude", text: $manualLongitude, keyboard: .decimalPad, capitalization: .never)

                                divider

                                Button {
                                    Task { @MainActor in
                                        await applyManualCoordinatesAndFetchWeather()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "mappin.and.ellipse")
                                        Text("Use Manual Coordinates")
                                        Spacer()
                                    }
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

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
                                        .foregroundColor(.white.opacity(0.72))
                                    DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }

                                divider

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("End")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.72))
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
                                    .foregroundColor(.white.opacity(0.72))

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
                                            .foregroundColor(.white.opacity(0.72))

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
                                        .foregroundColor(.white.opacity(0.82))
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
            if !newValue.isEmpty {
                addressLine = newValue
                locationName = newValue
            }
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
        .onChange(of: locationWeather.latitude) { _, newValue in
            if let lat = newValue {
                manualLatitude = lat.clean
                updateGPSCoordinatesText()
            }
        }
        .onChange(of: locationWeather.longitude) { _, newValue in
            if let lon = newValue {
                manualLongitude = lon.clean
                updateGPSCoordinatesText()
            }
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

    private func editorField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))

            TextField("", text: text, prompt: Text(title).foregroundColor(.white.opacity(0.35)))
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
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

    private func updateGPSCoordinatesText() {
        if let lat = locationWeather.latitude, let lon = locationWeather.longitude {
            gpsCoordinatesText = "Lat \(lat.clean), Lon \(lon.clean)"
        } else {
            gpsCoordinatesText = ""
        }
    }

    @MainActor
    private func applyManualCoordinatesAndFetchWeather() async {
        api.errorMessage = nil

        guard let lat = Double(manualLatitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(manualLongitude.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            api.errorMessage = "Enter valid latitude and longitude values."
            return
        }

        guard (-90...90).contains(lat), (-180...180).contains(lon) else {
            api.errorMessage = "Latitude must be between -90 and 90, and longitude must be between -180 and 180."
            return
        }

        do {
            try await locationWeather.applyManualCoordinates(latitude: lat, longitude: lon)
        } catch {
            api.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveJob() async {
        guard let teamID = api.teamID else {
            api.errorMessage = "No team membership found. Confirm team_members has a row for this user."
            return
        }

        guard !fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            api.errorMessage = "Field Name / ID is required."
            return
        }

        saving = true
        defer { saving = false }

        do {
            let nowISO = ISO8601DateFormatter().string(from: Date())

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
                latitude: locationWeather.latitude ?? existingJob?.latitude,
                longitude: locationWeather.longitude ?? existingJob?.longitude,
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
        guard let job = existingJob else {
            growerName = ""
            farmOwnerName = ""
            addressLine = ""
            city = ""
            stateRegion = ""
            zipCode = ""
            phone = ""
            contactEmail = ""
            fieldName = ""
            crop = ""
            acres = ""
            startDate = Date()
            endDate = Date()
            tempF = ""
            humidityPercent = ""
            windSpeedMPH = ""
            windDirection = ""
            barometricPressureInHg = ""
            dewPointF = ""
            locationName = ""
            weatherSummary = ""
            manualLatitude = ""
            manualLongitude = ""
            gpsCoordinatesText = ""
            notes = ""
            chemicalDrafts = [ChemicalDraft()]
            locationWeather.reset()
            return
        }

        fieldName = job.field_name ?? ""
        crop = job.crop ?? ""
        acres = job.total_acres_sprayed == 0 ? "" : job.total_acres_sprayed.clean

        growerName = job.grower_name ?? ""
        farmOwnerName = job.farm_owner_name ?? ""
        addressLine = job.address_line ?? ""
        city = job.city ?? ""
        stateRegion = job.state ?? ""
        zipCode = job.zip ?? ""
        phone = job.phone ?? ""
        contactEmail = job.email ?? ""

        tempF = job.temperature_f.cleanOrBlank
        humidityPercent = job.humidity_percent.cleanOrBlank
        windSpeedMPH = job.wind_speed_mph.cleanOrBlank
        windDirection = job.wind_direction ?? ""
        barometricPressureInHg = job.pressure_inhg.cleanOrBlank
        dewPointF = job.dew_point_f.cleanOrBlank

        locationName = job.address_line ?? ""
        weatherSummary = job.weather_summary ?? ""
        notes = job.notes ?? ""

        locationWeather.latitude = job.latitude
        locationWeather.longitude = job.longitude
        manualLatitude = job.latitude?.clean ?? ""
        manualLongitude = job.longitude?.clean ?? ""
        updateGPSCoordinatesText()

        if let startTime = job.start_time,
           let parsedStart = ISO8601DateFormatter().date(from: startTime) {
            startDate = parsedStart
        }

        if let endTime = job.end_time,
           let parsedEnd = ISO8601DateFormatter().date(from: endTime) {
            endDate = parsedEnd
        }

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
    @Published var isBootstrapping = true
    @Published var errorMessage: String?

    @Published var isAuthed = false
    @Published var userID: UUID?
    @Published var teamID: UUID?
    @Published var teamRole: String?

    var hasTeamMembership: Bool {
        teamID != nil
    }

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        await refreshAuthState()

        guard isAuthed, teamID != nil else {
            jobs = []
            return
        }

        await loadJobs()
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil

        do {
            _ = try await client.auth.signIn(email: email, password: password)
            await bootstrap()
        } catch {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil

        do {
            _ = try await client.auth.signUp(email: email, password: password)
            await bootstrap()
            if isAuthed, teamID == nil, errorMessage == nil {
                errorMessage = "Account created. Now add this user to team_members in Supabase so jobs can load."
            }
        } catch {
            errorMessage = "Create account failed: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        errorMessage = nil

        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }

        isAuthed = false
        userID = nil
        teamID = nil
        teamRole = nil
        jobs = []
    }

    func refreshAuthState() async {
        errorMessage = nil
        isAuthed = false
        userID = nil
        teamID = nil
        teamRole = nil

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
            guard let teamID else {
                jobs = []
                return
            }

            let rows: [SprayJobRow] = try await client
                .from("spray_jobs")
                .select()
                .eq("team_id", value: teamID.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            jobs = rows
        } catch {
            errorMessage = "Load jobs failed: \(error.localizedDescription)"
        }
    }

    func loadJobsForDate(_ date: Date, teamID: UUID) async throws -> [SprayJobRow] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let iso = ISO8601DateFormatter()

        let rows: [SprayJobRow] = try await client
            .from("spray_jobs")
            .select()
            .eq("team_id", value: teamID.uuidString)
            .gte("created_at", value: iso.string(from: start))
            .lt("created_at", value: iso.string(from: end))
            .order("created_at", ascending: true)
            .execute()
            .value

        return rows
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
            .eq("spray_job_id", value: jobID.uuidString)
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
                spray_job_id: jobID,
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
                .eq("spray_job_id", value: job.id.uuidString)
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
            .eq("spray_job_id", value: jobID.uuidString)
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

struct ChemicalRow: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var spray_job_id: UUID
    var chemical_name: String?
    var active_ingredient: String?
    var rate_per_acre: Double = 0
    var rate_unit: String = RateUnit.oz_ac.rawValue
    var acres_applied: Double = 0

    var descriptionLine: String {
        let name = chemical_name ?? "Chemical"
        let ai = active_ingredient?.isEmpty == false ? " (\(active_ingredient!))" : ""
        return "\(name)\(ai) - \(rate_per_acre.clean) \(rate_unit) on \(acres_applied.clean) ac"
    }
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

// MARK: - Location + Weather

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
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var lastUpdateText: String?

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
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func reset() {
        isLoading = false
        locationText = ""
        weatherSummary = ""
        temperatureF = ""
        humidityPercent = ""
        windSpeedMPH = ""
        windDirectionText = ""
        barometricPressureInHg = ""
        dewPointF = ""
        latitude = nil
        longitude = nil
        lastUpdateText = nil
        errorMessage = nil
        addressStreet = ""
        addressCity = ""
        addressState = ""
        addressZIP = ""
    }

    func requestLocationAndWeather() {
        errorMessage = nil
        isLoading = true

        guard CLLocationManager.locationServicesEnabled() else {
            isLoading = false
            errorMessage = "Location Services are turned off on this device."
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedAlways, .authorizedWhenInUse:
            latitude = nil
            longitude = nil
            manager.requestLocation()
            manager.startUpdatingLocation()

        case .restricted, .denied:
            isLoading = false
            errorMessage = "Location permission is denied. Enable While Using the App in Settings."

        @unknown default:
            isLoading = false
            errorMessage = "Unknown location authorization state."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocationAndWeather()

        case .restricted, .denied:
            isLoading = false
            errorMessage = "Location permission is denied or restricted."

        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                errorMessage = "Location permission was denied. Turn on While Using the App in Settings."
            case .locationUnknown:
                #if targetEnvironment(simulator)
                errorMessage = "Simulator does not have a live GPS fix. In Simulator, choose Features > Location and pick a test location, then try again."
                #else
                errorMessage = "Current location is temporarily unavailable. Try again in a moment."
                #endif
            case .network:
                errorMessage = "Location failed because of a network issue."
            default:
                errorMessage = "Location failed. Check location permissions and try again."
            }
        } else {
            errorMessage = "Location failed. Check location permissions and try again."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.max(by: { $0.timestamp < $1.timestamp }) else {
            isLoading = false
            errorMessage = "No location returned."
            return
        }

        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        lastUpdateText = Self.timestampFormatter.string(from: Date())

        manager.stopUpdatingLocation()

        Task {
            await fetchEverything(for: location)
        }
    }

    private func fetchEverything(for location: CLLocation) async {
        do {
            try await fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        } catch {
            isLoading = false
            errorMessage = "Weather fetch failed: \(error.localizedDescription)"
            return
        }

        do {
            try await reverseGeocode(location)
        } catch {
            addressStreet = ""
            addressCity = ""
            addressState = ""
            addressZIP = ""
            locationText = "\(location.coordinate.latitude.clean), \(location.coordinate.longitude.clean)"
        }

        isLoading = false
        errorMessage = nil
    }

    func applyManualCoordinates(latitude: Double, longitude: Double) async throws {
        errorMessage = nil
        isLoading = true

        self.latitude = latitude
        self.longitude = longitude
        lastUpdateText = Self.timestampFormatter.string(from: Date())

        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            try await fetchWeather(latitude: latitude, longitude: longitude)
        } catch {
            isLoading = false
            throw error
        }

        do {
            try await reverseGeocode(location)
        } catch {
            addressStreet = ""
            addressCity = ""
            addressState = ""
            addressZIP = ""
            locationText = "\(latitude.clean), \(longitude.clean)"
        }

        isLoading = false
    }

    private func reverseGeocode(_ location: CLLocation) async throws {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            locationText = "\(location.coordinate.latitude.clean), \(location.coordinate.longitude.clean)"
            return
        }

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
            "&wind_speed_unit=mph" +
            "&timezone=auto"

        guard let url = URL(string: urlString) else {
            throw WeatherError.badURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WeatherError.badResponse
        }

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

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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
        case badResponse

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "Weather URL could not be created."
            case .badResponse:
                return "Weather service returned an invalid response."
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

// MARK: - PDF Builder

enum DailyReportPDFBuilder {
    static func build(date: Date, jobs: [SprayJobRow], chemicalsByJob: [UUID: [ChemicalRow]]) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        let fileName = "Daily_Report_\(safeFileDate(date)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try renderer.writePDF(to: url) { context in
            var currentY: CGFloat = 36

            func newPage() {
                context.beginPage()
                currentY = 36
            }

            func draw(_ text: String, font: UIFont, color: UIColor = .black, x: CGFloat = 36, y: CGFloat, width: CGFloat = 540) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let rect = CGRect(x: x, y: y, width: width, height: 1000)
                text.draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            }

            newPage()
            draw("Ag Spray Drone Daily Report", font: .boldSystemFont(ofSize: 24), y: currentY)
            currentY += 34
            draw("Date: \(formatter.string(from: date))", font: .systemFont(ofSize: 14), y: currentY)
            currentY += 20
            draw("Total Jobs: \(jobs.count)", font: .systemFont(ofSize: 14), y: currentY)
            currentY += 18
            let totalAcres = jobs.reduce(0) { $0 + $1.total_acres_sprayed }
            draw("Total Acres Sprayed: \(totalAcres.clean)", font: .systemFont(ofSize: 14), y: currentY)
            currentY += 28

            for (index, job) in jobs.enumerated() {
                if currentY > 690 {
                    newPage()
                }

                draw("Job \(index + 1): \(job.field_name ?? "Unnamed Field")", font: .boldSystemFont(ofSize: 18), y: currentY)
                currentY += 24

                var lines: [String] = []
                lines.append("Grower: \(job.grower_name ?? "")")
                lines.append("Crop: \(job.crop ?? "")")
                lines.append("Acres: \(job.total_acres_sprayed.clean)")
                lines.append("Location: \(job.address_line ?? "") \(job.city ?? "") \(job.state ?? "")")
                lines.append("Weather: \(job.weather_summary ?? "")")
                lines.append("Temperature: \(job.temperature_f.cleanOrDash)°F   Humidity: \(job.humidity_percent.cleanOrDash)%")
                lines.append("Wind: \(job.wind_speed_mph.cleanOrDash) mph \(job.wind_direction ?? "")   Dew Pt: \(job.dew_point_f.cleanOrDash)°F")
                lines.append("Pressure: \(job.pressure_inhg.cleanOrDash) inHg")
                if let lat = job.latitude, let lon = job.longitude {
                    lines.append("Coordinates: Lat \(lat.clean), Lon \(lon.clean)")
                }
                if let notes = job.notes, !notes.isEmpty {
                    lines.append("Notes: \(notes)")
                }

                for line in lines where !line.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
                    draw(line, font: .systemFont(ofSize: 12), y: currentY)
                    currentY += 16
                }

                let chemicals = chemicalsByJob[job.id] ?? []
                if !chemicals.isEmpty {
                    currentY += 4
                    draw("Chemicals:", font: .boldSystemFont(ofSize: 13), y: currentY)
                    currentY += 18
                    for chemical in chemicals {
                        draw("• \(chemical.descriptionLine)", font: .systemFont(ofSize: 12), y: currentY, width: 520)
                        currentY += 16
                    }
                }

                currentY += 18
            }
        }

        return url
    }

    private static func safeFileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

    var cleanOrDash: String {
        switch self {
        case .some(let value):
            return value.clean
        case .none:
            return "-"
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
