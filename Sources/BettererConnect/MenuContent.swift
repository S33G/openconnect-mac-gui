import SwiftUI
import BetterConnectCore

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @State private var gatewayInput = ""
    @State private var addingGateway = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 30, weight: .medium)).foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Betterer Connect").font(.system(size: 17, weight: .semibold))
                    Text("A little less VPN friction.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Open as window", action: model.showWindow)
                    Button("Enable notifications…", action: model.enableNotifications)
                    Divider()
                    Button("Quit Betterer Connect") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("App options")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.symbol)
                        .font(.system(size: 26)).foregroundStyle(model.statusColor)
                        .frame(width: 36, height: 36)
                        .background(model.statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.statusTitle).font(.headline)
                        Text(model.statusDescription).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.machine.status == .connected, let since = model.machine.connectedSince {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let minutes = max(0, Int(ProcessInfo.processInfo.systemUptime - since) / 60)
                        Label(minutes < 1 ? "Connection confirmed just now" : "Observed connected for \(minutes) min", systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.machine.status == .connected, let server = model.sessionServer {
                    Text([server, model.sessionGroup].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let error = model.machine.lastError {
                    Button { model.copy(error.rawValue) } label: {
                        Label(error.rawValue, systemImage: "doc.on.doc").font(.system(.caption2, design: .monospaced))
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Copy error code")
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(model.statusColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.statusColor.opacity(0.16)))

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("GATEWAY").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    Spacer()
                    Button(addingGateway ? "Done" : "Add gateway") { addingGateway.toggle() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.purple)
                        .disabled(model.busy || model.machine.status == .connected || model.machine.status == .needsSSO)
                }
                if !model.gateways.isEmpty {
                    Picker("Gateway", selection: Binding(get: { model.machine.selectedGateway ?? "" }, set: model.choose)) {
                        ForEach(model.gateways, id: \.self) { host in Text(host).tag(host) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                        .disabled(model.busy || [.connected, .needsSSO, .reconnecting, .connecting].contains(model.machine.status))
                } else {
                    Text("No gateways configured").font(.callout).foregroundStyle(.secondary)
                }
                if addingGateway || model.gateways.isEmpty {
                    HStack {
                        TextField("vpn.example.com", text: $gatewayInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.addGateway(gatewayInput) }
                            .accessibilityLabel("Gateway hostname")
                        Button("Use") { model.addGateway(gatewayInput); addingGateway = false }
                            .disabled(Gateway.normalize(gatewayInput) == nil)
                    }
                    Text("Use the hostname supplied by your IT team.").font(.caption2).foregroundStyle(.secondary)
                }
                if model.machine.status == .needsSSO, let gateway = model.machine.selectedGateway {
                    Button("Copy gateway for Cisco") { model.copy(gateway) }.font(.caption)
                }
                if !model.config.preferredGroup.isEmpty {
                    Text("Suggested group: \(model.config.preferredGroup)").font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                if model.machine.status == .ciscoMissing {
                    Button("Open Self Service", action: model.openSelfService).buttonStyle(.borderedProminent).tint(.purple)
                    Button("Re-check", action: model.recheck).disabled(model.busy)
                } else if model.machine.status == .needsSSO {
                    Button("Continue in Cisco", action: model.openCisco).buttonStyle(.borderedProminent).tint(.blue)
                    Button("Cancel", action: model.cancelSignIn)
                } else {
                    if model.machine.status == .connected {
                        Button("Reconnect now", action: model.reconnectNow)
                            .buttonStyle(.borderedProminent).tint(.purple).disabled(model.busy)
                    } else {
                        Button(model.machine.status == .error ? "Retry connection" : "Connect", action: model.connect)
                            .buttonStyle(.borderedProminent).tint(.purple).disabled(!model.canConnect)
                    }
                    Button("Disconnect", action: model.disconnect).disabled(!model.canDisconnect)
                }
                if model.busy { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }.controlSize(.large)

            Divider()
            Toggle(isOn: Binding(get: { model.config.autoReconnect }, set: model.setAutoReconnect)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reconnect automatically").font(.callout)
                    Text(model.autoReconnectManaged ? "Managed by your organization" : "After wake, network changes, or a dropped tunnel")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch).controlSize(.small).disabled(model.autoReconnectManaged)

            HStack {
                Button("Open Cisco", action: model.openCisco)
                Spacer()
                Button { model.copyDiagnostics() } label: { Label("Copy diagnostics", systemImage: "doc.on.doc") }
            }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)

            if !model.note.isEmpty {
                Text(model.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                Text("Your sign-in stays with Cisco.")
                Spacer()
                Button("Re-check", action: model.recheck).buttonStyle(.plain).disabled(model.busy)
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(20).frame(width: 370).fixedSize(horizontal: false, vertical: true)
    }
}
