# Modelo de ameaças

> ⚠️ **Projeto de exemplo, NÃO auditado por terceiros. Não guarde segredos reais nele.** Este documento descreve o que o projeto tenta fazer, não uma garantia.

## Ativos
Os itens do cofre (senhas, segredos TOTP, chaves/tokens), a senha mestra e a chave de dados (DEK).

## O que protege, e contra quem

| Adversário | Proteção | Limite |
|---|---|---|
| **Quem lê os arquivos do app** (backup, aparelho roubado, extração do sandbox) | Tudo é AES-256-GCM (título incluso); DEK embrulhada por KEK derivada com PBKDF2-600k; autenticação detecta adulteração e troca de blobs (AAD = id); arquivos com proteção completa e fora de backup | Ataque offline à senha mestra: a força é a da senha (PBKDF2 não é memory-hard). Vazam contagem de itens, ids e datas de modificação |
| **Alguém com o aparelho desbloqueado por pouco tempo** | Auto-lock (background imediato + inatividade 30 s–15 min), valores ocultos por padrão, backoff exponencial de tentativas | O backoff é só da UI: não impede ataque offline |
| **Bisbilhoteiro visual / app switcher** | Cobertor opaco fora de `.active`; valores mascarados com "revelar" sob demanda | Quem olha por cima do ombro enquanto você revela |
| **Outros apps / outros aparelhos via clipboard** | `localOnly` (sem Universal Clipboard) + expiração de 30 s | Janela de 30 s; outros apps podem ler a área de transferência nesse intervalo (iOS 16+ pede confirmação) |
| **Troca de biometria** | `.biometryCurrentSet` invalida o acesso rápido | Só vale em aparelho real |
| **Rede** | O app não usa rede (ATS padrão, nenhum domínio) | — |
| **Vazamento por log** | O app não grava logs (nenhum `print`/`Logger` com dados); se algum for adicionado, usar `privacy: .private` | Revisão manual, sem varredura automática |

## O que NÃO protege
- **Aparelho comprometido** (jailbreak, malware, depuração), keylogger, screen recording: se o cofre está desbloqueado, o atacante vê tudo.
- **Memória:** `String`/`SymmetricKey` do Swift não são zerados; DEK e itens ficam na memória enquanto desbloqueado; um dump do processo os revela.
- **Senha mestra fraca ou reutilizada.** O indicador de força é uma heurística simples (não zxcvbn) e superestima senhas com padrões.
- **Perda da senha mestra = perda dos dados** (não há recuperação nem escrow).
- **Metadados em claro:** número de itens, ids, horários de modificação.
- **Backup exportado:** é cifrado com outra senha (PBKDF2 + AES-GCM), mas o arquivo vive onde o usuário o salvar; sem revogação.
- **Implementação não auditada, sem pentest, sem verificação formal.** Sem proteção contra ataques de canal lateral/tempo além do que CryptoKit/CommonCrypto fornecem.
- **Secure Enclave:** a DEK do desbloqueio biométrico é guardada no Keychain com controle de acesso biométrico, mas não é uma chave do Secure Enclave (ADR 0005); o simulador não valida nada disso.
- **Anti-tamper do app, jailbreak detection, certificate pinning** (sem rede): fora de escopo.

## Suposições
O iOS e o hardware são confiáveis; o usuário escolhe uma senha mestra longa e única; o aparelho tem código de acesso.
