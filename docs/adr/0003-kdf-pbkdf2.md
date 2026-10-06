# ADR 0003 — KDF: PBKDF2-HMAC-SHA256 (600 000 iterações)

- **Status:** aceito
- **Data:** 2026-10-06

## Contexto
A senha mestra precisa virar uma chave (KEK) resistente a força bruta offline.

## Decisão
**PBKDF2-HMAC-SHA256** via **CommonCrypto** (`CCKeyDerivationPBKDF`), **600 000 iterações** (recomendação OWASP 2023), salt aleatório de 16 bytes, saída de 32 bytes. Parâmetros e salt ficam no header (`iterations`, `salt`, `kdf`), então podem mudar sem quebrar cofres antigos. A senha é normalizada em NFKC (o mesmo "é" digitado composto ou decomposto gera a mesma chave). A senha mestra nunca é armazenada; o buffer de bytes é zerado com `memset_s`.
Testado com vetores conhecidos de PBKDF2-HMAC-SHA256 (c = 1, 2, 4096).

## Alternativas
- **Argon2id / scrypt:** são memory-hard e resistem melhor a GPU/ASIC, mas **não há implementação nos frameworks da Apple**; exigiria dependência de terceiros ou código de criptografia próprio, o que é pior para um projeto de referência (KISS, zero dependências). É o primeiro item de "Próximos passos".
- **CryptoKit:** não expõe PBKDF2 (só HKDF, que não serve para senha de baixa entropia).

## Consequências
(+) Nativo, rápido, auditável. (−) Sem dureza de memória: uma GPU testa muito mais candidatos por segundo que contra Argon2id. A força efetiva depende da senha mestra escolhida.
