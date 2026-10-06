import SwiftUI
import VaultCore

private struct EditorRequest: Identifiable {
  let id = UUID()
  let draft: ItemDraft
  let existing: VaultItem?
}

struct ItemListView: View {
  let kind: ItemKind
  @Environment(SessionModel.self) private var session
  @State private var query = ""
  @State private var favoritesOnly = false
  @State private var editor: EditorRequest?
  @State private var showGenerator = false
  @State private var pendingDelete: VaultItem?

  private var visible: [VaultItem] {
    ItemFilter(kind: kind, query: query, favoritesOnly: favoritesOnly).apply(to: session.items)
  }

  var body: some View {
    NavigationStack {
      List(visible) { item in
        NavigationLink(value: item.id) { ItemRow(item: item) }
          .swipeActions(edge: .leading) {
            Button(item.isFavorite ? "Desfavoritar" : "Favoritar", systemImage: item.isFavorite ? "star.slash" : "star") {
              Task { await session.toggleFavorite(item) }
            }
            .tint(.yellow)
          }
          .swipeActions(edge: .trailing) {
            Button("Excluir", systemImage: "trash", role: .destructive) { pendingDelete = item }
          }
      }
      .overlay {
        if visible.isEmpty {
          ContentUnavailableView(
            query.isEmpty ? "Nenhum item" : "Sem resultados", systemImage: kind.icon,
            description: Text(query.isEmpty ? "Toque em + para adicionar \(kind.singular)." : "Nada encontrado para a busca."))
        }
      }
      .navigationTitle(kind.title)
      .navigationDestination(for: UUID.self) { ItemDetailView(itemID: $0) }
      .searchable(text: $query, prompt: "Buscar")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            favoritesOnly.toggle()
          } label: {
            Image(systemName: favoritesOnly ? "star.fill" : "star")
          }
          .accessibilityLabel("Somente favoritos")
          .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
          if kind == .password {
            Button("Gerador de senha", systemImage: "wand.and.stars") { showGenerator = true }
          }
          Button("Adicionar", systemImage: "plus") {
            editor = EditorRequest(draft: ItemDraft(kind: kind), existing: nil)
          }
          .accessibilityIdentifier("addButton")
        }
      }
      .sheet(item: $editor) { request in
        ItemEditorView(draft: request.draft, existing: request.existing)
      }
      .sheet(isPresented: $showGenerator) { GeneratorView() }
      .confirmationDialog(
        "Excluir \"\(pendingDelete?.title ?? "")\"?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
        titleVisibility: .visible
      ) {
        Button("Excluir", role: .destructive) {
          if let item = pendingDelete { Task { await session.delete(id: item.id) } }
        }
        Button("Cancelar", role: .cancel) {}
      } message: {
        Text("Esta ação não pode ser desfeita.")
      }
    }
  }
}

struct ItemRow: View {
  let item: VaultItem

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(item.title).font(.headline)
        if item.isFavorite {
          Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("Favorito")
        }
      }
      switch item.content {
      case .password(let content):
        if !content.username.isEmpty { Text(content.username).font(.subheadline).foregroundStyle(.secondary) }
      case .authenticator(let content):
        AuthenticatorCodeView(content: content)
      case .authKey(let content):
        Text("\(content.keyKind.title) · ••••••••").font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
  }
}
