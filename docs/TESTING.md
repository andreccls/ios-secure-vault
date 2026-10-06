# Testes

Medido em 2026-10-06, Mac Apple Silicon, Xcode 26.6 (Swift 6.3.3), simulador iPhone 17 Pro (iOS 26.5).

```bash
make test-package  # swift test no VaultCore (macOS, ~0,02 s)
make test-unit     # testes do app no simulador (view-models, com fakes)
make test-ui       # XCUITests no simulador (fora do CI)
make test          # package + unit
make coverage      # cobertura de linhas do VaultCore (llvm-cov)
make lint          # swift-format --strict
```

## Pirâmide

| Nível | Onde | Resultado |
|---|---|---|
| Core (Swift Testing) | `VaultCore/Tests` | **84 testes em 15 suítes, verdes** |
| View-models (Swift Testing, simulador) | `AppTests` | **22 testes em 4 suítes, verdes** |
| UI (XCUITest, simulador) | `AppUITests` | __UI_STATUS__ |

### O que o core cobre (TDD em crypto/TOTP/KDF)
- PBKDF2-HMAC-SHA256: vetores conhecidos (c = 1, 2, 4096), determinismo, sensibilidade a salt/senha/iterações, normalização Unicode, parâmetros inválidos.
- AES-GCM: round-trip, adulteração em **cada posição** do blob, AAD errado, chave errada, entrada truncada, **5 000 nonces distintos**.
- Vault: criar/bloquear/desbloquear (inclusive "relançar o app"), senha errada, DEK aleatória por cofre, blob adulterado, **blob trocado entre itens (AAD)**, nada sensível em claro nos blobs, troca de senha sem recifrar itens, DEK exportada, header adulterado/malformado.
- Backoff: política (2, 4, 8 s, teto 300 s), cofre recusa até a senha **certa** durante o atraso, estado persiste entre execuções.
- TOTP: **vetores oficiais da RFC 6238 (SHA1/SHA256/SHA512, 6 instantes cada)**, zeros à esquerda, contagem regressiva, base32 (RFC 4648), parsing de `otpauth://` (válidos e 9 inválidos).
- Gerador (comprimento, classes, ambíguos, determinismo com RNG injetado, entropia), força da senha, auto-lock com relógio injetável, filtro/busca (nunca busca valores secretos), `FileVaultStorage` (disco, backup excluído), backup criptografado.

### O que o app cobre
`SessionModel` (fluxos de desbloqueio, backoff, lock por background e por inatividade com relógio injetado, biometria via fake, CRUD, troca de senha, backup), `ItemDraft`, `GeneratorModel`, `ClipboardService` (expiração e `localOnly` via spy).

### UI tests (simulador)
__UI_DETAIL__

## Cobertura

__COVERAGE__

### Excluído da medição, e por quê
- `KeychainBiometricKeyStore` (58 linhas): precisa de biometria/Secure Enclave reais; o simulador não os tem. A lógica de fallback ao redor é testada com fake em `SessionModel`.
- Views SwiftUI: verificadas por UI tests e screenshots, não por cobertura de linhas (0% nos testes unitários).
- `DemoData` e ganchos `-UITest*` (DEBUG apenas).

100% de linhas não prova ausência de bugs: não há fuzzing, nem testes de tempo constante, nem auditoria externa.

## Lint e build
`swift-format lint --strict` limpo; app com `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` e `SWIFT_STRICT_CONCURRENCY=complete` (Swift 6), sem avisos de compilação.
