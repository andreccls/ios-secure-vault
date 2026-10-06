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
| UI (XCUITest, simulador) | `AppUITests` | **6 testes, verdes** (simulador iPhone 17 Pro, ~2 min no total) |

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
| Teste | Verifica |
|---|---|
| `testCreateVaultAndAddPassword` | criar cofre (senha + confirmação) e adicionar uma senha |
| `testAddAuthenticatorShowsLiveCode` | adicionar autenticador por segredo base32; código `NNN NNN` visível |
| `testLockAndUnlock` | bloquear em Ajustes, senha errada mostra erro, senha certa desbloqueia |
| `testDeleteRequiresConfirmation` | excluir abre confirmação; dispensar mantém o item; confirmar remove |
| `testGoingToBackgroundLocksTheVault` | **auto-lock real**: botão Home e voltar ao app pede a senha mestra |
| `testSecretsAreMaskedUntilRevealed` | valor "oculto" até tocar em revelar |

Rodam contra uma build DEBUG com `-UITestReset` (cofre temporário novo e KDF de 1 000 iterações; esse gancho não existe em Release). **Fora do CI** (boot/teclado do simulador são instáveis em runner hospedado). Dois achados reais durante a depuração: (1) um `simultaneousGesture` na raiz engolia toques em botões da barra (corrigido com um reconhecedor passivo, `TouchActivity`); (2) no iOS 26 o `confirmationDialog` no iPhone é um popover só com a ação destrutiva (cancelar = tocar fora). Os testes dependem do tamanho de texto padrão do simulador: com Dynamic Type "accessibility XXL" ativo, o botão "Bloquear agora" fica fora da tela e `testLockAndUnlock` falha; `scripts/screenshots.sh` restaura o tamanho no fim.

## Cobertura

**VaultCore** (`swift test --enable-code-coverage`, linhas):

| Arquivo | Linhas | Cobertura |
|---|---|---|
| Crypto/* (AES-GCM, PBKDF2, Zeroize) | 65 | **100%** |
| TOTP/TOTP.swift, Base32.swift | 46 | **100%** |
| TOTP/AuthenticatorContent.swift | 61 | 95,1% (3 linhas: ramos defensivos) |
| Vault/* (Vault, Backup, FileStorage, Attempt, Storage) | 220 | **100%** |
| Domain, Passwords, AutoLock | 158 | **100%** |
| Security/KeychainBiometricKeyStore.swift | 60 | 0% (excluído, ver abaixo) |
| **Total medido** | 610 (63 não cobertas) | 89,7% |
| **Total sem o Keychain** | 550 (3 não cobertas) | **99,5%** |

Meta ≥ 90% atingida **excluindo** o único arquivo que exige hardware; incluindo-o o total é 89,7% (abaixo da meta, sem maquiar). Crypto e TOTP puros: 100%; `AuthenticatorContent` (parser/validação) 95,1%.

**App** (`xccov`, testes unitários + UI juntos, linhas): **76,1%** (1 785/2 346). Por arquivo: `SessionModel` 99,0%, `ItemDraft` 100%, `GeneratorModel` 95,0%, `UnlockView` 93,4%, `ItemListView` 91,6%, `RootView` 91,9%, `ItemDetailView` 85,4%, `ItemEditorView` 80,4%, `SettingsView` 56,9% (backup/importação/alterar senha não têm UI test), `GeneratorView` 0% (só vista nos screenshots), `DemoData` 4% (DEBUG, usado só pelos screenshots).

### Excluído da medição, e por quê
- `KeychainBiometricKeyStore` (58 linhas): precisa de biometria/Secure Enclave reais; o simulador não os tem. A lógica de fallback ao redor é testada com fake em `SessionModel`.
- Views SwiftUI: verificadas por UI tests e screenshots, não por cobertura de linhas (0% nos testes unitários).
- `DemoData` e ganchos `-UITest*` (DEBUG apenas).

100% de linhas não prova ausência de bugs: não há fuzzing, nem testes de tempo constante, nem auditoria externa.

## Lint e build
`swift-format lint --strict` limpo; app com `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` e `SWIFT_STRICT_CONCURRENCY=complete` (Swift 6), sem avisos de compilação.
