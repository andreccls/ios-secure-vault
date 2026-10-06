# ADR 0007 — Testes, lint e geração do projeto

- **Status:** aceito
- **Data:** 2026-10-06

## Decisão
- **Swift Testing** (`@Test/#expect`) no core (`swift test`, TDD em crypto/TOTP/KDF) e nos view-models do app (com fakes); **XCTest/XCUITest** só para UI, que o Swift Testing não cobre.
- **Lint: `swift-format`** (`xcrun swift-format lint --strict`) — vem com o Xcode 26, nada a instalar, e a configuração é um `.swift-format` versionado. SwiftLint exigiria brew/SPM plugin.
- **Projeto Xcode gerado por XcodeGen** (`project.yml` versionado; `.xcodeproj` no `.gitignore`): diff legível, sem conflitos de `pbxproj`. Pré-requisito: `brew install xcodegen` (o Makefile roda `xcodegen generate`).
- **CI** (macOS): lint + `swift test` + build + testes unitários do app. **UI tests ficam fora do CI**: dependem de boot/teclado do simulador e são instáveis em runner hospedado; rode `make test-ui`.
- Ganchos de teste (`-UITestReset`, `-UITestSeed`, `-UITestShield`) existem **só em DEBUG**: uma build Release nunca pode rodar com o KDF reduzido (1 000 iterações) usado nos UI tests.
