//
//  TripSetupViews.swift
//  Dipstick
//

import SwiftUI
import SwiftData

// MARK: - Progress

/// How far along automatic drives are for a car: Always location access,
/// a linked car connection, and the Shortcuts automations (done once a
/// drive has been recorded, since the app can't see Shortcuts).
struct TripSetupProgress {
    let hasAlwaysLocation: Bool
    let hasConnection: Bool
    let hasDrives: Bool

    @MainActor
    init(vehicle: Vehicle, recorder: TripRecorder) {
        hasAlwaysLocation = recorder.canRecordInBackground
        hasConnection = !vehicle.connections.isEmpty
        hasDrives = !vehicle.sortedTrips.isEmpty
    }

    var stepsDone: Int { [hasAlwaysLocation, hasConnection, hasDrives].filter { $0 }.count }
    var stepCount: Int { 3 }
    var isComplete: Bool { hasAlwaysLocation && hasConnection && hasDrives }
}

/// On the Stats tab until automatic drives are set up: what it's for, how
/// far along, and a button to the guide.
struct TripSetupCard: View {
    let vehicle: Vehicle
    let onSetUp: () -> Void
    let onLearnMore: () -> Void
    @Environment(TripRecorder.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let progress = TripSetupProgress(vehicle: vehicle, recorder: recorder)
        Group {
            if !progress.isComplete {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "car.side")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.accent)
                        Text("Set up automatic drives")
                            .font(.dipstick(16, .semibold, relativeTo: .headline))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(progress.stepsDone) of \(progress.stepCount)")
                            .font(.readout(13, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                    }
                    Text("Dipstick records each drive on its own and splits it into city and highway miles, so you'll see your car's real city and highway MPG. About 3 minutes to set up.")
                        .font(.dipstick(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(action: onSetUp) {
                            Text(progress.stepsDone == 0 ? "Set up" : "Continue setup")
                                .font(.dipstick(14, .semibold, relativeTo: .body))
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(Theme.accent))
                        }
                        .buttonStyle(.borderless)
                        Button("How it works", action: onLearnMore)
                            .font(.dipstick(14, .semibold, relativeTo: .body))
                            .foregroundStyle(Theme.accentText)
                            .buttonStyle(.borderless)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel(radius: Theme.Radius.field, border: Theme.accent.opacity(0.5))
            }
        }
        .onChange(of: scenePhase) { if scenePhase == .active { recorder.refreshAuthorization() } }
    }
}

// MARK: - Setup guide

/// Three steps: Always location, link the car's connection, and the two
/// Shortcuts automations (checked off once a drive is recorded).
struct TripSetupView: View {
    let vehicle: Vehicle

    @Environment(TripRecorder.self) private var recorder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var linkMessage: String?
    @State private var isShowingLearnMore = false
    @AppStorage("trips.askedForAlways") private var triedAlways = false
    /// Shortcuts moved Automation under a new shortcut's Edit in iOS 27;
    /// starts on the phone's own version.
    @State private var shortcutsVersion: ShortcutsVersion = .current

    enum ShortcutsVersion: Hashable {
        case newer, older
        static var current: ShortcutsVersion {
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? .newer : .older
        }
    }

    var body: some View {
        let progress = TripSetupProgress(vehicle: vehicle, recorder: recorder)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Button("Done") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    vehicle.chip
                    Text("AUTOMATIC DRIVES")
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.bottom, 4)

                Text("When your phone connects to \(vehicle.name), Dipstick starts recording the drive in the background and stops when you park. Each drive is split into city and highway miles. After a few tanks, that gives your car's real city and highway MPG.")
                    .font(.dipstick(15, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button { isShowingLearnMore = true } label: {
                    Label("How it works and what's saved", systemImage: "info.circle")
                        .font(.dipstick(14, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)

                step(1, "Allow location: Always", done: progress.hasAlwaysLocation) { locationStep }
                step(2, "Link \(vehicle.name)", done: progress.hasConnection) { linkStep }
                step(3, "Add two Shortcuts automations", done: progress.hasDrives) {
                    detail("Two Shortcuts automations tell Dipstick when you get in and out of the car. Apps can't add these themselves, so it takes a minute in the Shortcuts app.")
                    Picker("iOS version", selection: $shortcutsVersion) {
                        Text("iOS 27").tag(ShortcutsVersion.newer)
                        Text("iOS 26 or older").tag(ShortcutsVersion.older)
                    }
                    .pickerStyle(.segmented)
                    automationSteps(start: true)
                    automationSteps(start: false)
                    actionButton("Open Shortcuts", icon: "arrow.up.right.square") {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    }
                    detail(progress.hasDrives
                           ? "Done: drives are being recorded. They show under Drives on the Stats tab."
                           : "Then take a drive. When you park, it shows under Drives on the Stats tab, and this step is checked off. If it doesn't, check that both automations are on and set to Run Immediately.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .sheet(isPresented: $isShowingLearnMore) { TripsLearnMoreView() }
        .onChange(of: scenePhase) { if scenePhase == .active { recorder.refreshAuthorization() } }
    }

    // MARK: Steps

    @ViewBuilder
    private var locationStep: some View {
        detail("Drives start with Dipstick closed, so it needs location set to Always. Location is only used while a drive is recording, and your route is never saved.")
        if !recorder.canRecordInBackground {
            let canAsk = recorder.authorizationStatus == .notDetermined
                || (recorder.authorizationStatus == .authorizedWhenInUse && !triedAlways)
            actionButton(canAsk ? "Allow location" : "Open Settings", icon: "location") {
                if canAsk {
                    triedAlways = recorder.authorizationStatus == .authorizedWhenInUse
                    recorder.requestAlwaysAuthorization()
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            if !canAsk {
                detail("In Settings, tap Location and choose Always.")
            }
        }
    }

    @ViewBuilder
    private var linkStep: some View {
        detail("This is how Dipstick knows which car a drive is in. Sit in \(vehicle.name) with it on and your phone connected by CarPlay or Bluetooth, then tap Link. A car can have both; link each one.")
        ForEach(vehicle.connections, id: \.id) { connection in
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                Text(connection.name)
                    .font(.dipstick(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
            }
        }
        actionButton("Link the current connection", icon: "link") {
            guard let connection = CarConnection.current() else {
                linkMessage = "Not connected to a car right now. Connect by CarPlay or Bluetooth and try again."
                return
            }
            if vehicle.knowsConnection(connection.id) {
                linkMessage = "\(connection.name) is already linked."
            } else {
                vehicle.addConnection(connection)
                modelContext.saveNow()
                linkMessage = "Linked \(connection.name)."
            }
        }
        if let linkMessage {
            detail(linkMessage)
        }
    }

    /// One automation's steps: Connects → Start Trip, or Disconnects → Stop Trip.
    private func automationSteps(start: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(start ? "When you get in" : "When you get out")
                .font(.dipstick(14, .semibold, relativeTo: .body))
                .foregroundStyle(Theme.text)
            if shortcutsVersion == .newer {
                numbered(1, "In Shortcuts, tap + at the bottom to make a new shortcut, then Edit at the top right, then Automation.")
            } else {
                numbered(1, "In Shortcuts, tap Automation, then +.")
            }
            numbered(2, "Choose CarPlay (or Bluetooth, then pick your car).")
            numbered(3, "Choose \(start ? "Connects" : "Disconnects"), and Run Immediately. Turn off Notify When Run.")
            numbered(4, "Tap Next, search for Dipstick, and choose \(start ? "Start Trip" : "Stop Trip"). Tap Done.")
            if !start {
                detail("Recording ends once you've been parked for 3 minutes, so a quick stop or the car's screen restarting doesn't end the drive.")
            }
        }
        .padding(.top, 4)
    }

    // MARK: Pieces

    private func step<Content: View>(_ number: Int, _ title: String, done: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? Theme.accent : Theme.selectedFill)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onAccent)
                    } else {
                        Text("\(number)").font(.readout(13, relativeTo: .caption)).foregroundStyle(Theme.text)
                    }
                }
                .frame(width: 26, height: 26)
                Text(title)
                    .font(.dipstick(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.text)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(done ? "Done" : "")
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: Theme.Radius.field)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.dipstick(13, relativeTo: .footnote))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).")
                .font(.readout(13, relativeTo: .footnote))
                .foregroundStyle(Theme.accentText)
            Text(text)
                .font(.dipstick(14, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.dipstick(14, .semibold, relativeTo: .body))
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.panelBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Learn more

/// How automatic drives work: recording, which car, city vs highway, the
/// MPG math, and what's kept.
struct TripsLearnMoreView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Button("Done") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    Text("HOW IT WORKS")
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }

                section("Recording a drive", icon: "record.circle", paragraphs: [
                    "When your phone connects to your car, your Shortcuts automation tells Dipstick to start. It records in the background with the screen locked, using your phone's GPS to measure distance and speed.",
                    "When the car disconnects, Dipstick waits until you've been parked for 3 minutes, then saves the drive. If you're still driving (the car's screen restarted, say), it keeps going.",
                ])
                section("Which car", icon: "car.2", paragraphs: [
                    "Each car's CarPlay or Bluetooth connection has its own ID, which you link once. Drives in a car Dipstick doesn't know show on Home as drives to sort; pick the car once and it's remembered.",
                ])
                section("City or highway", icon: "road.lanes", paragraphs: [
                    "Each drive is cut into half-mile stretches. A stretch is highway when it averages at least 45 mph and never drops below 25 mph. Everything else is city, including stop-and-go traffic on the freeway, since that's how your engine experiences it.",
                    "This is similar to the EPA's fuel economy tests: the highway test averages about 48 mph with no stops, and the city test about 21 mph with frequent stops.",
                ])
                section("From miles to MPG", icon: "function", paragraphs: [
                    "Every full tank gives one equation: the gallons you put in equal the tank's city miles divided by city MPG, plus its highway miles divided by highway MPG.",
                    "Tanks with different mixes of city and highway let Dipstick solve for both numbers. Until there's enough variety, it assumes highway is about 30% better than city, and real tanks quickly outweigh that. It says \"rough estimate\" until there are at least 3 tanks with different mixes.",
                    "A tank only counts when recorded drives cover most of its miles, so a forgotten trip doesn't skew it. Combined MPG is always your real miles divided by real gallons.",
                ])
                section("What's saved", icon: "lock", paragraphs: [
                    "Location is only used while a drive is recording. When it ends, Dipstick keeps two numbers: city miles and highway miles, with the date and car. Your route, locations and speeds are never saved.",
                    "Everything stays on your iPhone. Nothing is sent to us or anyone else. Backups go only to the folder you choose, like your own iCloud Drive.",
                ])
                section("Battery", icon: "battery.75percent", paragraphs: [
                    "GPS uses some battery while a drive is recording, about like a navigation app. Nothing runs between drives.",
                ])
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
    }

    private func section(_ title: String, icon: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.dipstick(16, .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.dipstick(14, relativeTo: .body))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
