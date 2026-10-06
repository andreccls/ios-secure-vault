import SwiftUI
import VaultCore

struct ItemDetailView: View {
  let itemID: UUID
  @Environment(SessionModel.self) private var session
  @Environment(\.dismiss) private var dismiss
  @State private var editing: ItemDraft?
  @State private var confirmDelete = false

  var body: some View {
    Group {
      if let item = session.item(id: itemID) {
        List {
          content(of: item)
          Section {
            LabeledContent("Atualizado", value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
          }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
              Task { await session.toggleFavorite(item) }
            } label: {
              Image(systemName: item.isFavorite ? "star.fill" : "star")
            }
            .accessibilityLabel(item.isFavorite ? "Remover dos favoritos" : "Favoritar")
            Button("Editar") { editing = ItemDraft(item: item) }
            Button("Excluir", systemImage: "trash", role: .destructive) { confirmDelete = true }
              .accessibilityIdentifier("deleteButton")
          }
        }
        .sheet(item: Binding(get: { editing.map { DraftBox(draft: $0) } }, set: { if $0 == nil { editing = nil } })) { box in
          ItemEditorView(draft: box.draft, existing: item)
        }
        .confirmationDialog("Excluir \"\(item.title)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
          Button("Excluir", role: .destructive) {
            Task {
              await session.delete(id: item.id)
              dismiss()
            }
          }
          Button("Cancelar", role: .cancel) {}
        } message: {
          Text("Esta ação não pode ser desfeita.")
        }
      } else {
        ContentUnavailableView("Item removido", systemImage: "trash")
      }
    }
  }

  @ViewBuilder
  private func content(of item: VaultItem) -> some View {
    switch item.content {
    case .password(let content):
      Section {
        FieldRow(label: "Usuário", value: content.username)
        FieldRow(label: "Senha", value: content.password, isSecret: true)
        FieldRow(label: "URL", value: content.url)
      }
      if !content.notes.isEmpty { Section("Notas") { Text(content.notes) } }
    case .authenticator(let content):
      Section {
        AuthenticatorCodeView(content: content, large: true)
        FieldRow(label: "Emissor", value: content.issuer)
        FieldRow(label: "Conta", value: content.account)
        FieldRow(label: "Segredo (base32)", value: content.secret, isSecret: true)
        LabeledContent("Algoritmo", value: "\(content.algorithm.rawValue) · \(content.digits) dígitos · \(content.period) s")
      }
    case .authKey(let content):
      Section {
        LabeledContent("Tipo", value: content.keyKind.title)
        FieldRow(label: "Valor secreto", value: content.secret, isSecret: true)
      }
      if !content.notes.isEmpty { Section("Notas") { Text(content.notes) } }
    }
  }
}

private struct DraftBox: Identifiable {
  let id = UUID()
  let draft: ItemDraft
}

/// A labelled value: masked by default, revealed on demand, copyable (clipboard expires, see `ClipboardService`).
struct FieldRow: View {
  let label: String
  let value: String
  var isSecret = false
  @State private var revealed = false
  @Environment(ClipboardService.self) private var clipboard

  var body: some View {
    if !value.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        HStack(alignment: .firstTextBaseline) {
          Text(isSecret && !revealed ? String(repeating: "•", count: min(max(value.count, 8), 16)) : value)
            .font(isSecret ? .system(.body, design: .monospaced) : .body)
            .textSelection(.enabled)
            .accessibilityLabel(isSecret && !revealed ? "\(label), oculto" : "\(label), \(value)")
            .accessibilityIdentifier("value-\(label)")
          Spacer(minLength: 8)
          if isSecret {
            Button {
              revealed.toggle()
            } label: {
              Image(systemName: revealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(revealed ? "Ocultar \(label)" : "Revelar \(label)")
          }
          Button {
            clipboard.copy(value, label: label)
          } label: {
            Image(systemName: "doc.on.doc")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Copiar \(label)")
        }
      }
      .padding(.vertical, 2)
    }
  }
}
