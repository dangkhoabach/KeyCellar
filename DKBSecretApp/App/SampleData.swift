#if DEBUG
import DKBSecretCore
import Foundation

/// Debug › Seed Sample Data: thirty fake items across every kind, with
/// projects, tags, expiries and one rotated key, for walking the UI without
/// typing real secrets in. Debug builds only.
enum SampleData {
    static func seed(services: AppServices) async {
        let vault = services.vault
        let projects = services.projects
        let names = ["CaPheSuaDa", "Northwind Studio", "Contoso Group", "DKB Monitor", "MyWebsite"]
        let projectIds = names.compactMap { try? projects.findOrCreate(name: $0).id }
        let services = ["Resend", "GitHub", "AWS", "Stripe", "Slack", "OpenAI", "Cloudflare", "Vercel"]
        let envs: [DeploymentEnvironment?] = [.prod, .staging, .dev, nil]

        for i in 0..<30 {
            let kind = SecretKind.allCases[i % SecretKind.allCases.count]
            let service = services[i % services.count]
            var item = SecretItem(
                kind: kind,
                title: "\(service) – sample \(i + 1)",
                projectId: projectIds[i % projectIds.count],
                service: kind == .apiKey ? service : nil,
                environment: envs[i % envs.count],
                url: kind == .login || kind == .apiKey ? "https://\(service.lowercased()).com" : nil,
                username: kind == .login || kind == .sshKey ? "user\(i)" : nil,
                favorite: i % 7 == 0,
                expiresAt: i % 4 == 0 ? Date().addingTimeInterval(TimeInterval((i % 3) * 5 + 2) * 86_400) : (i % 4 == 1 ? Date().addingTimeInterval(120 * 86_400) : nil)
            )
            if kind == .sshKey { item.metadata = ["host": "10.0.0.\(i)", "publicKey": "ssh-ed25519 AAAAC3Nz…sample\(i)"] }
            var secrets: [String: SecretBytes] = [:]
            switch kind {
            case .apiKey: secrets["key"] = SecretBytes("sample-key-\(i)-not-real")
            case .login: secrets["password"] = SecretBytes("SamplePass\(i)!")
            case .sshKey:
                secrets["privateKey"] = SecretBytes("-----BEGIN OPENSSH PRIVATE KEY-----\nsample\(i)\n-----END OPENSSH PRIVATE KEY-----")
                secrets["passphrase"] = SecretBytes("phrase\(i)")
            case .envSet:
                secrets["env.DATABASE_URL"] = SecretBytes("postgres://u:p@localhost/db\(i)")
                secrets["env.RESEND_API_KEY"] = SecretBytes("re_sample_\(i)")
                secrets["env.PORT"] = SecretBytes("300\(i % 10)")
            case .secureNote: secrets["body"] = SecretBytes("Recovery codes for sample \(i):\n1111-2222\n3333-4444")
            }
            if i % 3 == 0 { secrets["notes"] = SecretBytes("Created from the dashboard on day \(i).") }
            try? await vault.create(item, tags: [["prod", "email", "ci", "infra"][i % 4]], secrets: secrets)
            if i == 0 {
                try? await vault.rotate(itemId: item.id, field: "key", newValue: SecretBytes("sample-key-0-rotated"))
                try? await vault.rotate(itemId: item.id, field: "key", newValue: SecretBytes("sample-key-0-rotated-again"))
            }
        }
    }
}
#endif
