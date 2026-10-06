# ADR 0002 — Módulo `VaultCore` (Swift Package local) sem UI

- **Status:** aceito
- **Data:** 2026-10-06

## Contexto
Criptografia, TOTP, persistência e regras de bloqueio são o que mais precisa de teste rápido e de fronteira clara.

## Decisão
Um **Swift Package local** (`VaultCore/`) com domínio + crypto + TOTP + persistência. **Não importa SwiftUI/UIKit**; o app (`App/`) depende dele, nunca o contrário. A regra `App → VaultCore` é imposta **pela estrutura de módulos**: o compilador recusa `import SwiftUI` no package? Não — mas o package não declara essa dependência de produto de UI e `swift test` roda no macOS sem simulador, então um import de UI quebraria o build do pacote. Não há teste de arquitetura separado (YAGNI).
- Portas no core (`VaultStorage`, `BiometricKeyStore`) com implementações reais (`FileVaultStorage`, `KeychainBiometricKeyStore`) e fakes (`InMemoryVaultStorage`).
- `swift test` roda a suíte do core em ~0,02 s.

## Alternativas
- Tudo no target do app: testes só no simulador, lentos, e mistura de UI com crypto.
- Vários pacotes (Crypto, TOTP, Storage): fronteiras sem ganho neste tamanho.

## Consequências
(+) Testes rápidos, cobertura medida por linha no core. (−) `public` em muita coisa; `KeychainBiometricKeyStore` precisa de dispositivo e fica fora da cobertura.
