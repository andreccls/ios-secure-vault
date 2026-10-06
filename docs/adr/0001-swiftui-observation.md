# ADR 0001 — SwiftUI + Observation, sem bibliotecas de UI/estado

- **Status:** aceito
- **Data:** 2026-10-06

## Contexto
O app é pequeno (4 abas, formulários, uma tela de desbloqueio) e o estado sensível (itens decifrados) precisa viver só na memória e sumir ao bloquear.

## Decisão
- **SwiftUI** com `NavigationStack`/`TabView`; **Observation** (`@Observable`) para o estado de apresentação (`SessionModel`, `GeneratorModel`, `ClipboardService`), injetado por `.environment(...)`. Sem Combine, sem `ObservableObject`, sem biblioteca de DI: a raiz de composição (`AppComposition`) escolhe as implementações concretas.
- **Swift 6 em modo estrito** (`SWIFT_STRICT_CONCURRENCY=complete`, avisos como erro): modelos de UI em `@MainActor`, o cofre é um `actor`.
- Deployment target **iOS 17** (mínimo para `@Observable`/SwiftData-era APIs); compilado com o SDK 26.5.
- Telas finas: toda regra (validação do formulário, filtro, força da senha) fica em tipos testáveis sem SwiftUI (`ItemDraft`, `GeneratorModel`, `ItemFilter`).

## Alternativas
- **TCA/Redux:** mais cerimônia do que o domínio pede; viola KISS/YAGNI.
- **UIKit:** mais código sem ganho aqui.

## Consequências
- (+) Pouco código, sem dependências. (−) `simultaneousGesture` para detectar atividade do usuário é uma heurística (digitação é tratada à parte no editor).
