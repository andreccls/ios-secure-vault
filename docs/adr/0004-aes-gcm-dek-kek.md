# ADR 0004 — AES-256-GCM com DEK aleatória embrulhada por KEK

- **Status:** aceito
- **Data:** 2026-10-06

## Decisão
```
senha mestra --PBKDF2--> KEK --AES-GCM--> wrappedDEK (header)
DEK (256 bits aleatórios) --AES-GCM, AAD = id do item--> um blob por item
```
- **CryptoKit** `AES.GCM`, nonce aleatório de 96 bits por operação (layout `nonce || ciphertext || tag`). Um teste sela o mesmo texto 5 000 vezes e exige nonces distintos.
- **AAD = "securevault.item.v1" + id do item:** copiar o blob de um item sobre o de outro é detectado (teste "blob swapped").
- **Trocar a senha mestra** só recria salt/KEK e re-embrulha a DEK; os itens não são recifrados (teste confirma blobs idênticos).
- **keyCheck:** texto conhecido selado com a DEK, para validar uma DEK vinda do Keychain biométrico (que pode estar obsoleta após reinstalar o app).
- Senha errada = falha de autenticação do GCM ao desembrulhar a DEK (sem verificador separado).

## Alternativas
- Derivar a chave dos itens direto da senha: trocar a senha exigiria recifrar tudo.
- ChaChaPoly: equivalente; AES-GCM tem aceleração em hardware Apple.

## Consequências
Nonces aleatórios de 96 bits: seguro até ~2^32 mensagens por chave (NIST SP 800-38D), muito além de um cofre pessoal.
