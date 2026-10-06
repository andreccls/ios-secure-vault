# ADR 0005 — Keychain + biometria para o desbloqueio rápido

- **Status:** aceito
- **Data:** 2026-10-06

## Decisão
Ao ativar Face ID/Touch ID, o app guarda a **DEK** num item do Keychain com `SecAccessControl(.biometryCurrentSet)` e `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
- só legível com o aparelho desbloqueado e mediante biometria (aplicada pelo Secure Enclave);
- **nunca** migra para outro aparelho, backup ou iCloud Keychain;
- invalida se o conjunto de biometria mudar (alguém cadastrando outro rosto não herda o acesso).
`LocalAuthentication` (`LAContext.evaluatePolicy`) pede a biometria; o contexto já autenticado é reutilizado na leitura do Keychain (um só prompt). Qualquer falha (cancelar, invalidar, item sumiu) **cai para a senha mestra**; só o cancelamento mantém a biometria habilitada.

## Honestidade sobre o Secure Enclave
O SE só guarda chaves EC; a DEK em si é material de chave comum protegido por controle de acesso do Keychain. Uma alternativa mais forte (chave EC no SE + ECIES para embrulhar a DEK) não foi feita (YAGNI), e **nada disso é validável no simulador**: o simulador não tem SE nem biometria real, então `KeychainBiometricKeyStore` não tem teste automatizado (a lógica de fallback em `SessionModel` é testada com um fake).
