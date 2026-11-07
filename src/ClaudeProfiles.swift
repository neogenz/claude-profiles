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
    private var personalCode: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Vos profils") {
                    ForEach(model.profiles) { profile in
                        HStack(spacing: 10) {
                            Image(systemName: profile.managed ? "person.crop.square" : "house")
                                .foregroundStyle(profile.managed ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).font(.headline)
                                Text(profile.managed ? (profile.shared ? "Configuration commune" : "Sans synchronisation") : "Configuration source")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.pid != nil { Circle().fill(.green).frame(width: 7, height: 7).help("Instance ouverte") }
                        }.padding(.vertical, 5).tag(profile.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 245)
        } detail: {
            if let profile = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.name).font(.largeTitle.bold())
                                Text(profile.pid == nil ? "Instance fermée" : "Instance ouverte")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(profile.pid == nil ? "Ouvrir Claude" : "Afficher Claude") { model.launch(profile) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                        }
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Configuration").font(.headline)
                                if profile.managed {
                                    Toggle("Actualiser depuis le profil personnel au lancement", isOn: Binding(
                                        get: { profile.shared },
                                        set: { shared in
                                            if shared { confirmSharing = true }
                                            else { model.change(["configure", profile.id, "--independent"], message: "Synchronisation désactivée. Les fichiers actuels sont conservés.") }
                                        }))
                                    if profile.shared {
                                        Button("Synchroniser maintenant") {
                                            model.change(["sync", profile.id], message: "Configuration commune synchronisée.")
                                        }.disabled(profile.pid != nil)
                                        if profile.pid != nil { Text("Quittez cette instance Claude pour synchroniser.").font(.caption).foregroundStyle(.secondary) }
                                    }
                                } else {
                                    Text("Source des profils synchronisés. Les modifications faites ici seront reprises à leur prochain lancement.")
                                        .foregroundStyle(.secondary)
                                }
                                let config = profile.shared ? personalCode : profile.code
                                HStack {
                                    Button(profile.shared ? "Réglages communs" : "Réglages JSON") { model.open(config + "/settings.json", edit: true) }
                                    Button("Instructions communes (CLAUDE.md)") { model.open(personalCode + "/CLAUDE.md", edit: true) }
                                    Button("Dossier de configuration") { model.open(config) }
                                }
                                if profile.shared { Text("Éditez la source commune ici : les copies du profil sont écrasées lors de la synchronisation.").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }
                        if profile.managed {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Partagé ou propre à ce profil").font(.headline)
                                    sharingSummary(shared: profile.shared)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            }
                        }
                        GroupBox {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Emplacements").font(.headline)
                                pathRow("Claude Code", profile.code)
                                Divider()
                                pathRow("Données Desktop", profile.data)
                                Divider()
                                pathRow(profile.managed ? "Raccourci" : "Application", profile.app, reveal: true)
                            }.padding(10)
                        }
                        if profile.managed {
                            Text("Le nom est un repère local, pas une identité de compte. Vérifiez le compte connecté dans Claude. Les plugins s’installent dans chaque profil.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }.padding(28).frame(maxWidth: 920, alignment: .leading)
                }.disabled(model.busy)
            } else {
                Text(model.busy ? "Chargement des profils…" : "Sélectionnez ou ajoutez un profil.").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 940, minHeight: 710)
        .toolbar {
            Button { newName = ""; newShared = true; adding = true } label: {
                Label("Ajouter un profil", systemImage: "plus")
            }.disabled(model.busy)
            Button { model.refresh() } label: { Label("Actualiser", systemImage: "arrow.clockwise") }.disabled(model.busy)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.busy ? "Opération en cours…" : model.notice).font(.caption).textSelection(.enabled)
                Spacer()
            }.padding(.horizontal, 16).padding(.vertical, 9).background(.bar)
        }
        .onAppear { model.refresh() }
        .onChange(of: model.selection) { _, _ in model.notice = "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .alert("Opération impossible", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Réactiver la configuration commune ?", isPresented: $confirmSharing) {
            Button("Annuler", role: .cancel) {}
            Button("Réactiver") {
                if let profile = selected { model.change(["configure", profile.id], message: "Configuration commune activée pour le prochain lancement.") }
            }
        } message: { Text("À la prochaine synchronisation, les réglages et fichiers communs du profil remplaceront vos modifications locales. La connexion et les plugins seront conservés.") }
        .sheet(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ajouter un profil Claude").font(.title2.bold())
                Text("Un nouveau dossier et un raccourci seront créés. Vous vous connecterez ensuite au compte souhaité dans Claude.").foregroundStyle(.secondary)
                TextField("Nom, par exemple travail ou client", text: $newName)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Nom du profil")
                Text("Lettres minuscules, chiffres et tirets ; commencez par une lettre. 31 caractères maximum.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Actualiser la configuration depuis le profil personnel", isOn: $newShared)
                sharingSummary(shared: newShared)
                if validName {
                    Text("Code : ~/.claude-\(newName)\nDesktop : ~/Library/Application Support/claude-\(newName)")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Annuler") { adding = false }.keyboardShortcut(.cancelAction)
                    Button("Créer le profil") {
                        let name = newName
                        adding = false
                        model.change(["install", name] + (newShared ? [] : ["--independent"]), message: "Profil \(name.uppercased()) créé. Ouvrez Claude pour vous connecter.", select: name)
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(!validName || model.profiles.contains { $0.id == newName })
                }
                if model.profiles.contains(where: { $0.id == newName }) { Text("Ce profil existe déjà.").foregroundStyle(.red) }
            }.padding(28).frame(width: 620)
        }
    }

    // Mirrors sync() in claude-profiles.py: keep both lists in step with what it copies and skips.
    private func sharingSummary(shared: Bool) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(shared ? "Copié depuis ~/.claude à chaque lancement" : "Copié une seule fois, à la création")
                    .font(.subheadline.bold())
                bullet("Réglages : settings.json et settings.local.json, hooks et barre d’état compris")
                bullet("Skills, agents, commandes, règles et styles (ajouts seulement : un fichier retiré de ~/.claude reste dans le profil)")
                bullet("Serveurs MCP globaux de ~/.claude.json, avec leurs éventuels identifiants de service")
                Text("Lu directement, jamais copié").font(.subheadline.bold()).padding(.top, 4)
                bullet("Instructions ~/.claude/CLAUDE.md, pour tout projet situé dans votre dossier personnel")
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text("Propre à ce profil").font(.subheadline.bold())
                bullet("Compte Claude connecté et données de l’application Desktop")
                bullet("Plugins et marketplaces installés")
                bullet("Historique, sessions et mémoire des projets")
                bullet("Choix par projet : serveurs MCP activés, dossiers approuvés")
                bullet("Secrets jamais copiés : apiKeyHelper et variables contenant TOKEN, SECRET, PASSWORD, API_KEY ou AUTH")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bullet(_ text: String) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Text("•") }
            .font(.callout).foregroundStyle(.secondary)
    }

    private func pathRow(_ title: String, _ path: String, reveal: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold())
                Text(path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button("Copier") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
                .help("Copier le chemin de \(title)")
            Button("Finder") {
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                else { model.open(path) }
            }.help("Afficher \(title) dans le Finder")
        }
    }
}

@main
struct ClaudeProfilesApp: App {
    var body: some Scene {
        WindowGroup("Profils Claude") { ProfilesView() }
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
