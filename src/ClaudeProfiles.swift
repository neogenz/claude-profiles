import AppKit
import SwiftUI

struct Profile: Decodable, Identifiable {
    let id: String
    let name: String
    let code: String
    let data: String
    let app: String
    let shared: Bool
    let managed: Bool
    let pid: Int32?
}

final class ProfilesModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var selection: String? = "__personal__"
    @Published var busy = false
    @Published var notice = ""
    @Published var error: String?
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude-Profile-Launcher")

    func run(_ arguments: [String], success: @escaping (String) -> Void) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = self.root.appendingPathComponent("python")
            process.arguments = [self.root.appendingPathComponent("claude-profiles.py").path] + arguments
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    self.busy = false
                    if process.terminationStatus == 0 { success(text) }
                    else { self.error = text.isEmpty ? "L’opération a échoué." : text }
                }
            } catch {
                DispatchQueue.main.async { self.busy = false; self.error = error.localizedDescription }
            }
        }
    }

    func refresh() {
        guard !busy else { return }
        run(["list"]) { text in
            do { self.profiles = try JSONDecoder().decode([Profile].self, from: Data(text.utf8)) }
            catch { self.error = "Impossible de lire les profils : \(error.localizedDescription)" }
        }
    }

    func change(_ arguments: [String], message: String, select: String? = nil) {
        run(arguments) { _ in
            self.notice = message
            if let select { self.selection = select }
            self.refresh()
        }
    }

    func launch(_ profile: Profile) {
        if let pid = profile.pid, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            app.activate(options: [.activateAllWindows])
            return
        }
        if profile.managed {
            change(["launch", profile.id], message: "Claude \(profile.name) ouvert. Connectez le compte souhaité dans cette fenêtre.")
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: profile.app), configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    if let error { self.error = error.localizedDescription }
                    self.refresh()
                }
            }
        }
    }

    func open(_ path: String, edit: Bool = false) {
        guard FileManager.default.fileExists(atPath: path) else {
            error = "Cet emplacement n’existe pas encore :\n\(path)"
            return
        }
        let url = URL(fileURLWithPath: path)
        if edit {
            guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                error = "TextEdit est introuvable."; return
            }
            NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { DispatchQueue.main.async { self.error = error.localizedDescription } }
            }
        } else if !NSWorkspace.shared.open(url) {
            error = "Impossible d’ouvrir \(path)"
        }
    }
}

struct ProfilesView: View {
    @StateObject private var model = ProfilesModel()
    @State private var adding = false
    @State private var newName = ""
    @State private var newShared = true
    @State private var confirmSharing = false
    private var selected: Profile? { model.profiles.first { $0.id == model.selection } }
    private var validName: Bool { newName.range(of: "^[a-z][a-z0-9-]{0,30}$", options: .regularExpression) != nil }
    private var nameTaken: Bool { model.profiles.contains { $0.id == newName } }
    private var personalCode: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.profiles) { profile in
                    HStack(spacing: 10) {
                        Image(systemName: profile.managed ? "person.crop.circle" : "house")
                            .foregroundStyle(profile.managed ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            Text(profile.managed ? (profile.shared ? "Synchronisé" : "Indépendant") : "Source commune")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.pid != nil { Circle().fill(.green).frame(width: 7, height: 7).help("Ouvert") }
                    }.padding(.vertical, 4).tag(profile.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            if let profile = selected {
                detail(profile)
            } else {
                Text(model.busy ? "Chargement…" : "Sélectionnez un profil.").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .toolbar {
            Button { newName = ""; newShared = true; adding = true } label: {
                Label("Nouveau profil", systemImage: "plus")
            }.disabled(model.busy).help("Nouveau profil")
        }
        .safeAreaInset(edge: .bottom) {
            if model.busy || !model.notice.isEmpty {
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.busy ? "Opération en cours…" : model.notice).font(.caption).textSelection(.enabled)
                    Spacer()
                }.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
            }
        }
        .onAppear { model.refresh() }
        .onChange(of: model.selection) { _, _ in model.notice = "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .alert("Opération impossible", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Synchroniser avec Personnel ?", isPresented: $confirmSharing) {
            Button("Annuler", role: .cancel) {}
            Button("Synchroniser") {
                if let profile = selected { model.change(["configure", profile.id], message: "Synchronisé à la prochaine ouverture.") }
            }
        } message: { Text("À la prochaine ouverture, les réglages, skills et MCP de Personnel remplaceront ceux de ce profil. Le compte et les plugins sont conservés.") }
        .sheet(isPresented: $adding) { newProfileSheet }
    }

    private func detail(_ profile: Profile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name).font(.largeTitle.bold())
                        HStack(spacing: 6) {
                            Circle().fill(profile.pid == nil ? Color.secondary.opacity(0.4) : .green).frame(width: 7, height: 7)
                            Text(profile.pid == nil ? "Fermé" : "Ouvert").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(profile.pid == nil ? "Ouvrir Claude" : "Afficher Claude") { model.launch(profile) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                if profile.managed { syncCard(profile) } else { sourceCard }
                VStack(alignment: .leading, spacing: 10) {
                    caption("Emplacements")
                    place("Code", profile.code)
                    place("Desktop", profile.data)
                    place(profile.managed ? "Raccourci" : "Application", profile.app, reveal: true)
                }
            }
            .padding(28).frame(maxWidth: 640, alignment: .leading)
        }.disabled(model.busy)
    }

    private func syncCard(_ profile: Profile) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                switchRow("Synchroniser avec Personnel",
                          profile.shared ? "Mis à jour à chaque ouverture de Claude." : "Ce profil garde sa propre configuration.",
                          isOn: Binding(get: { profile.shared }, set: { shared in
                              if shared { confirmSharing = true }
                              else { model.change(["configure", profile.id, "--independent"], message: "Synchronisation désactivée.") }
                          }))
                Divider()
                sharingSummary(shared: profile.shared)
                HStack(spacing: 18) {
                    Button("Modifier le commun dans Personnel") { model.selection = "__personal__" }
                    if !profile.shared {
                        Button("Réglages de ce profil") { model.open(profile.code + "/settings.json", edit: true) }
                    }
                }.buttonStyle(.link)
            }.padding(10)
        }
    }

    private var sourceCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Partagé avec vos autres profils").font(.headline)
                let synced = model.profiles.filter { $0.managed && $0.shared }.map(\.name)
                if !synced.isEmpty {
                    Text("Utilisé aussi par " + synced.joined(separator: ", ") + ".")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Modifier CLAUDE.md") { model.open(personalCode + "/CLAUDE.md", edit: true) }
                    Button("Modifier settings.json") { model.open(personalCode + "/settings.json", edit: true) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
    }

    private var newProfileSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Nouveau profil").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                TextField("Nom, par exemple travail", text: $newName)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Nom du profil")
                Text(nameTaken ? "Ce profil existe déjà." : "Minuscules, chiffres et tirets.")
                    .font(.caption).foregroundStyle(nameTaken ? Color.red : .secondary)
            }
            switchRow("Synchroniser avec Personnel",
                      newShared ? "Mis à jour à chaque ouverture de Claude." : "Ce profil gardera sa propre configuration.",
                      isOn: $newShared)
            sharingSummary(shared: newShared)
            HStack {
                Spacer()
                Button("Annuler") { adding = false }.keyboardShortcut(.cancelAction)
                Button("Créer") {
                    let name = newName
                    adding = false
                    model.change(["install", name] + (newShared ? [] : ["--independent"]),
                                 message: "Profil \(name.uppercased()) créé. Ouvrez Claude pour connecter le compte.", select: name)
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!validName || nameTaken)
            }
        }.padding(24).frame(width: 440)
    }

    // Mirrors sync() in claude-profiles.py: keep both lists in step with what it copies and skips.
    private func sharingSummary(shared: Bool) -> some View {
        let synced = ["settings.json", "Skills, agents et commandes", "Serveurs MCP globaux"]
        return HStack(alignment: .top, spacing: 24) {
            column("Commun", ["CLAUDE.md"] + (shared ? synced : []))
            column("Propre à ce profil", ["Compte Claude", "Plugins", "Historique", "Clés d’API"] + (shared ? [] : synced))
        }
    }

    private func column(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption(title)
            ForEach(items, id: \.self) { Text($0) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private func switchRow(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
    }

    private func place(_ title: String, _ path: String, reveal: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Text((path as NSString).abbreviatingWithTildeInPath)
                .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string)
                model.notice = "Chemin copié : " + path
            } label: { Image(systemName: "doc.on.doc") }.help("Copier le chemin")
            Button {
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                else { model.open(path) }
            } label: { Image(systemName: "folder") }.help("Afficher dans le Finder")
        }.buttonStyle(.borderless)
    }
}

@main
struct ClaudeProfilesApp: App {
    var body: some Scene {
        WindowGroup("Profils Claude") { ProfilesView() }
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
