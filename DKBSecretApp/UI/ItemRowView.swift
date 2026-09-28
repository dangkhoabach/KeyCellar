import DKBSecretCore
import SwiftUI

struct ItemRowView: View {
    let item: SecretItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.title).lineLimit(1)
                    if item.favorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 4) {
                    if let environment = item.environment {
                        Circle().fill(environment.color).frame(width: 7, height: 7)
                    }
                    Text(subtitle).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let expires = item.expiresAt {
                ExpiryLabel(date: expires)
            }
        }
        .padding(.vertical, 2)
    }

    private var kindName: String {
        switch item.kind {
        case .apiKey: "API Key"
        case .login: "Login"
        case .sshKey: "SSH Key"
        case .envSet: ".env Set"
        case .secureNote: "Secure Note"
        case .recoveryCodes: "Recovery Codes"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let service = item.service, !service.isEmpty { parts.append(service) }
        else if let username = item.username, !username.isEmpty { parts.append(username) }
        else { parts.append(String(localized: String.LocalizationValue(kindName), bundle: AppLocale.bundle)) }
        if let used = item.lastUsedAt {
            parts.append(used.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

/// "in 3 days" in orange under 14 days, red once expired.
struct ExpiryLabel: View {
    let date: Date

    var body: some View {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        Text(date, format: .relative(presentation: .numeric))
            .font(.caption2)
            .foregroundStyle(days < 0 ? Color.red : (days <= SidebarSelection.expiringWindowDays ? Color.orange : Color.secondary))
    }
}
