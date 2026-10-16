# Inventário de hash, anonimização e criptografia

**Versão:** 2026-10-16  
**Escopo:** bancos PostgreSQL operacional e analítico do Mottainai  
**Objetivo:** indicar onde cada dado protegido é armazenado, qual tratamento é
aplicado e se o valor pode ser recuperado.

## Como interpretar os tratamentos

| Tratamento | Pode recuperar o original? | Uso correto |
|---|---:|---|
| AES-256-GCM | Sim, somente com a chave externa correta | Confidencialidade e integridade de nome e contatos que precisam ser abertos por serviço autorizado |
| HMAC-SHA-256 | Não | Índice cego para pesquisa por igualdade sem expor o valor original |
| SHA-256 tokenizado | Não | Pseudonimização, correlação e comparação determinística |
| BCrypt | Não | Senhas e códigos de baixa entropia; a aplicação apenas verifica correspondência |
| Mascaramento | Não a partir da máscara | Exibição segura em telas e logs |
| Minimização | Não integralmente | Manter somente o atributo necessário, como o ano em vez da data de nascimento |
| Redação | Não | Substituir valores sensíveis em JSON por `[REDACTED]` |
| Exclusão | Não se aplica | Impedir que a tabela ou o campo seja copiado para o banco analítico |

Hash não é criptografia. SHA-256, HMAC e BCrypt são irreversíveis. Somente os
campos `*_ciphertext` podem ser descriptografados, e as chaves AES/HMAC nunca
devem ser armazenadas no PostgreSQL.

## Banco operacional

**Nome usado na máquina:** `MOTTAINAI`  
**Nome lógico documentado:** `mottainai_operational`  
**Schema:** `mottainai`

### Identidade de funcionários

| Tabela | Campo | Tipo de proteção | Formato ou regra | Recuperável? |
|---|---|---|---|---:|
| `employee` | `cpf` | SHA-256 tokenizado | `CPF_SHA256_<64 hex>`; token legado `CPF_TKN_<6 hex>` é aceito durante compatibilidade | Não |
| `app_user` | `cpf` | SHA-256 tokenizado | Cópia sincronizada de `employee.cpf` | Não |
| `app_user` | `password_hash` | BCrypt | Formato `$2a$`, `$2b$` ou `$2y$`; nunca guarda a senha | Não |
| `employee_private_data` | `name_ciphertext` | AES-256-GCM | Ciphertext autenticado com tag | Sim, com chave externa |
| `employee_private_data` | `name_nonce` | Nonce criptográfico | 12 bytes; único por operação e chave | Não é dado pessoal recuperável |
| `employee_private_data` | `name_token` | HMAC-SHA-256 | `HMAC256_V<versão>_<64 hex>` | Não |
| `employee_private_data` | `name_masked` | Mascaramento | Valor próprio para apresentação | Não |
| `employee_private_data` | `email_ciphertext` | AES-256-GCM | Ciphertext autenticado com tag | Sim, com chave externa |
| `employee_private_data` | `email_nonce` | Nonce criptográfico | 12 bytes; único por operação e chave | Não é dado pessoal recuperável |
| `employee_private_data` | `email_token` | HMAC-SHA-256 | Índice cego versionado | Não |
| `employee_private_data` | `email_masked` | Mascaramento | Exemplo: `a***@dominio.com` | Não |
| `employee_private_data` | `phone_ciphertext` | AES-256-GCM | Ciphertext autenticado com tag | Sim, com chave externa |
| `employee_private_data` | `phone_nonce` | Nonce criptográfico | 12 bytes; único por operação e chave | Não é dado pessoal recuperável |
| `employee_private_data` | `phone_token` | HMAC-SHA-256 | Índice cego versionado | Não |
| `employee_private_data` | `phone_masked` | Mascaramento | Exibição parcial do telefone | Não |
| `employee_private_data` | `key_version` | Metadado criptográfico | Identifica a versão da chave existente no KMS/secret manager | Não contém a chave |

Na versão final, `employee.name`, `employee.email`, `employee.phone` e
`app_user.email` não existem. Eles aparecem somente durante a migração em duas
fases. O estado `LEGACY_TOKEN` preserva temporariamente tokens antigos; o estado
`ENCRYPTED` exige envelope AES-GCM, HMAC, versão de chave e `encrypted_at`.

`app_user.firebase_uid` é a identidade externa usada no login. Atualmente é um
valor restrito por RLS e privilégios, mas não é hash nem ciphertext. Ele não é
enviado ao banco analítico.

### Clientes

| Tabela | Campo | Tipo de proteção | Formato ou regra | Recuperável? |
|---|---|---|---|---:|
| `customer` | `full_name` | SHA-256 tokenizado | `CUS_SHA256_<64 hex>` | Não |
| `customer` | `cpf` | SHA-256 tokenizado | `CPF_SHA256_<64 hex>` | Não |
| `customer` | `email` | SHA-256 tokenizado | `EMAIL_SHA256_<64 hex>` | Não |
| `customer` | `phone` | SHA-256 tokenizado | `PHONE_SHA256_<64 hex>` | Não |
| `customer` | `external_auth_uid` | SHA-256 tokenizado | `AUTH_SHA256_<64 hex>` | Não |
| `customer` | `address_token` | SHA-256 tokenizado | `ADDR_SHA256_<64 hex>`; `address_id` deve permanecer nulo | Não |
| `customer` | `birth_year` | Minimização | Guarda somente o ano; `birth_date` é removido | Não recupera a data completa |
| `customer_auth` | `login_email` | SHA-256 tokenizado | `EMAIL_SHA256_<64 hex>` | Não |
| `customer_auth` | `password_hash` | BCrypt | Hash adaptativo de senha | Não |
| `customer_auth` | `recovery_token_hash` | BCrypt | Código de recuperação de baixa entropia | Não |

Esses campos do módulo de clientes continuam irreversíveis. Caso o negócio
precise exibir nome ou contato original do cliente no futuro, será necessária
uma migration específica para envelopes AES-GCM; os SHA-256 atuais não podem
ser convertidos de volta ao valor original.

### Empresas, lojas e fornecedores

| Tabela | Campo | Tipo de proteção aceito | Formato ou regra | Recuperável? |
|---|---|---|---|---:|
| `company` | `email` | SHA-256 ou máscara legada | `EMAIL_SHA256_<64 hex>` ou formato mascarado validado | Não |
| `company` | `phone` | SHA-256 ou máscara legada | `PHONE_SHA256_<64 hex>` ou formato mascarado validado | Não |
| `retail_store` | `email` | SHA-256 ou máscara legada | Token ou máscara; pode ser nulo | Não |
| `retail_store` | `phone` | SHA-256 ou máscara legada | Token ou máscara; pode ser nulo | Não |
| `supplier` | `email` | SHA-256 ou máscara legada | Token ou máscara; pode ser nulo | Não |
| `supplier` | `phone` | SHA-256 ou máscara legada | Token ou máscara; pode ser nulo | Não |

Máscara legada não é criptografia. Ela serve somente para exibição e não deve
ser usada como fonte de recuperação do contato.

### Venda, autenticação e integração

| Tabela | Campo | Tipo de proteção | Regra | Recuperável? |
|---|---|---|---|---:|
| `sales_transaction` | `customer_document` | SHA-256 tokenizado | `DOC_SHA256_<64 hex>` | Não |
| `staff_session` | `refresh_token_hash` | SHA-256 | 64 caracteres hexadecimais; somente o hash do refresh token é persistido | Não |
| `password_reset_token` | `token_hash` e `code_hash` | BCrypt ou SHA-256 | Aliases sincronizados; BCrypt para `PASSWORD_RESET` e SHA-256 hexadecimal para `EMPLOYEE_INVITATION` | Não |
| `legacy_sync_record` | `payload_sha256` | SHA-256 técnico | Detecta alteração/repetição do payload sem armazenar o payload transferido | Não |
| `audit_log` | `old_data`, `new_data` | Redação recursiva | Chaves pessoais, senhas e tokens são substituídos por `[REDACTED]` | Não |
| `audit_log_archive` | `old_data`, `new_data` | Herda o conteúdo já redigido | Arquiva a auditoria sem reintroduzir o valor original | Não |
| `integration_log` | `payload`, `response` | Redação recursiva | Trigger remove valores de chaves sensíveis antes da gravação | Não |
| `error_log` | `parameters` | Redação recursiva | Trigger remove valores de chaves sensíveis antes da gravação | Não |

Os hashes técnicos de payload demonstram igualdade ou integridade; não
significam que o JSON original seja anônimo. Por isso payloads e logs continuam
com acesso restrito e não são replicados para analytics.

## Banco analítico

**Nome usado na máquina:** `MOTTAINAI_ANALITICO`  
**Nome lógico documentado:** `mottainai_analytics`  
**Schema:** `mottainai_analytics`

### Campos armazenados com proteção

| Tabela | Campo | Tipo de proteção | Finalidade | Recuperável? |
|---|---|---|---|---:|
| `dim_customer` | `anonymous_key` | Pseudonimização por UUID aleatório | Identificador de exposição analítica sem CPF, nome ou contato | Não diretamente; a correlação interna ainda exige governança |
| `dim_customer` | `birth_year` | Minimização | Análise por faixa etária sem data de nascimento | Não recupera a data completa |
| `stg_operational_row` | `payload_sha256` | SHA-256 técnico gerado | Integridade e detecção de repetição do payload permitido | Não |
| `etl_rejected_row` | `payload_sha256` | SHA-256 técnico | Evidência da rejeição sem guardar o payload proibido | Não |

`dim_employee` mantém somente `employee_id`, loja, papel, estado e datas de
carga. Não recebe CPF, nome, e-mail, telefone, ciphertext, nonce, HMAC ou máscara.

### Dados bloqueados no analítico

| Origem operacional | Tratamento no analítico |
|---|---|
| `employee_private_data` | Tabela inteira marcada como `EXCLUDED` |
| `app_user`, `customer_auth`, `staff_session`, `password_reset_token` | Tabelas inteiras marcadas como `EXCLUDED` |
| CPF, e-mail, telefone, nome completo, documento e Firebase UID | Chaves rejeitadas recursivamente no staging |
| `*_ciphertext`, `*_nonce`, `*_token`, `*_masked`, `key_version`, `encrypted_at` | Chaves rejeitadas recursivamente no staging |
| Auditoria, logs, payloads de integração e `event_queue` | Fontes excluídas do contrato ETL |

O banco analítico não possui chave AES e não descriptografa dados. Receber um
ciphertext no BI também seria exposição desnecessária; por isso a regra é
exclusão, e não simples cópia do valor cifrado.

## Responsabilidade de cada camada

| Camada | Responsabilidade |
|---|---|
| Backend/RPA autorizado | Normalizar o valor, criptografar com AES-256-GCM, gerar nonce e HMAC, produzir máscara e informar a versão da chave |
| KMS/secret manager | Guardar e rotacionar chaves AES/HMAC, controlar acesso e registrar uso |
| Banco operacional | Validar formatos, aplicar constraints, RLS, privilégios e armazenar somente o formato protegido definido |
| ETL das 02:00 | Selecionar somente campos permitidos, reconciliar contagens e rejeitar chaves proibidas |
| Banco analítico | Manter apenas dados minimizados ou pseudonimizados necessários ao BI |

## Regras obrigatórias

1. Nunca registrar chaves AES/HMAC, senha aberta, token aberto ou dado pessoal
   original no banco, código-fonte ou log.
2. Usar chaves distintas para AES e HMAC e nonce AES-GCM novo a cada operação.
3. Descriptografar somente no serviço autorizado, após validar tenant e
   permissão; não criar função SQL pública de descriptografia.
4. Não tentar “abrir” SHA-256, HMAC ou BCrypt. Esses formatos são irreversíveis.
5. Não executar a finalização da migration enquanto API/RPA ainda dependerem de
   `employee.name/email/phone` ou `app_user.email`.
6. Tratar pseudonimização como proteção de dados, não como anonimização absoluta:
   se houver possibilidade de correlação, LGPD e controle de acesso continuam aplicáveis.
