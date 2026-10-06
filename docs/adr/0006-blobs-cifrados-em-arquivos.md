# ADR 0006 — Persistência: um blob cifrado por item, em arquivos (sem SwiftData)

- **Status:** aceito
- **Data:** 2026-10-06

## Decisão
`FileVaultStorage`: um diretório com `header.json` (KDF + DEK embrulhada, não secretos), `attempts.json` (contador do backoff) e `<uuid>.item` (ciphertext AES-GCM). Escrita atômica; no iOS, `.completeFileProtection`; o diretório é marcado `isExcludedFromBackup`.

**Em claro:** id (nome do arquivo), tamanho e data de modificação do arquivo, parâmetros do KDF. **Cifrado:** tudo o mais, **inclusive o título** — a busca é feita **em memória** depois do desbloqueio.

## Por que não SwiftData/Core Data/SQLite
Guardam colunas em claro por padrão (para consultar), deixam rastros em WAL/journal e acoplariam o core a um framework de persistência. Com blobs opacos, o storage é um protocolo de 7 métodos, trivial de trocar e de fazer fake.

## Consequências
(+) Nada sensível em repouso; zero migração de esquema. (−) Vaza a **contagem** de itens e quando mudaram; carrega tudo na memória (centenas de itens, ok); sem consulta indexada.
