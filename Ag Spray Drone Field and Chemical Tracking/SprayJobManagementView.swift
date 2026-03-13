import SwiftUI

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

                    if jobs.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(jobs) { job in
                                Button {
                                    editingJob = job
                                } label: {
                                    jobRow(job)
                                }
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

    private var jobs: [SprayJobRow] {
        api.sampleJobs
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spray Job Manager")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    Text("Track jobs, weather, chemicals, and acreage")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()
            }

            HStack(spacing: 12) {
                dashboardCard(title: "Total Jobs", value: "\(jobs.count)")
                dashboardCard(title: "Open Jobs", value: "\(jobs.filter { !$0.is_closed }.count)")
                dashboardCard(title: "Acres", value: totalAcresText)
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

            Text("Create your first spray job to start tracking fields, conditions, and chemical use.")
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

    private var totalAcresText: String {
        jobs.reduce(0) { $0 + $1.total_acres_sprayed }.clean
    }
}
