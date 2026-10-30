# Documentação concreta do banco operacional Mottainai

**Versão:** 2026-10-30
**Database:** `mottainai_operational`
**Schema:** `mottainai`
**Finalidade:** servir como fonte transacional oficial para a operação e como contrato de dados para a API.

## Decisão de arquitetura

O banco operacional registra cadastros e transações que precisam de consistência imediata: usuários, catálogo, compra, recebimento, lote, estoque, inventário, PDV, venda, fiscal, promoção, fidelidade, transferência, doação e descarte. O banco analítico não participa do commit dessas operações.

Os scripts instaláveis ficam exclusivamente em `database/operational`. Esta documentação fica fora dessa pasta para que a pasta de scripts possa ser usada diretamente por migrações e automações.

## Aderência aos requisitos das disciplinas

| Disciplina | Evidência implementada | Situação |
|---|---|---|
| Desenvolvimento operacional | Transações, regras, funções, triggers, auditoria, RLS, índices, testes e outbox idempotente | Atende no escopo do banco |
| Modelagem de dados | PKs, FKs, cardinalidades, restrições, normalização dos cadastros e separação entre cabeçalho/item | Atende |
| Business Intelligence | Produz eventos confirmados e dados rastreáveis para fatos/dimensões, sem executar BI no OLTP | Atende como fonte |
| RF01-RF03 | Vendas, perdas, promoções e eventos necessários para dashboards e exportações | Base disponível; exportação pertence à API/BI |
| RF04 | Funcionários, contas, papéis, permissões e auditoria | Atende |
| RF05 | Vendas e documentos fiscais por competência mensal | Base disponível; geração SPED exige serviço fiscal |
| RF06-RF11 | Estoque, lotes, validade, venda, alertas, ações e feedback operacional | Atende como fonte do motor |
| RF12-RF18 | Produtos, fornecedores, inventário, transferências, perdas, recebimento, custo e reposição | Atende; parser de XML pertence à API |
| RF19-RF21 | Geofence, promoções, cliente e fidelidade | Atende a persistência; push/chatbot ficam na aplicação |
| RF22-RF25 | PDV, pagamento, fiscal, turno, caixa e cancelamento | Atende a persistência; sincronização offline exige protocolo na API |

## Contrato de dados protegidos

O banco operacional segue o mesmo conceito acordado para o banco legado. O
backend de origem trata o dado antes da persistência e o PostgreSQL valida o
formato recebido. Documento de venda e identificadores externos usam tokens
SHA-256 prefixados; senhas e códigos de recuperação de baixa entropia usam
BCrypt. Nome, CPF, e-mail e telefone do funcionário usam criptografia
reversível autenticada AES-256-GCM e valor mascarado. A decisão final não usa
HMAC nem índice cego nesses quatro campos.

Após a finalização, `employee` e `app_user` não guardam CPF. O CPF cifrado fica
somente em `employee_private_data`, junto do nonce e da versão da chave. A API
não faz busca por CPF ou e-mail: contas ativas são localizadas pelo
`firebase_uid`, e convites pendentes pelo token de convite.

O módulo de clientes não passa pelo legado, mas segue o mesmo princípio. Nome,
CPF, e-mail, telefone e UID externo chegam tokenizados. A data de nascimento é
reduzida para `birth_year`, e o endereço residencial é representado somente por
`address_token`; não há vínculo com o endereço operacional de lojas. Quando a
aplicação precisa recuperar os valores originais autorizados, ela também grava
um envelope AES-256-GCM opcional em `customer_private_data`. Os tokens continuam
sendo o contrato de busca e o envelope nunca segue para o banco analítico.

As chaves AES ficam exclusivamente em KMS/secret manager, com versão e
rotação; não são gravadas nem recebidas por função do PostgreSQL. Somente um
serviço autorizado pode abrir o envelope. AES-GCM garante confidencialidade e
autenticidade. Nonces de 96 bits devem ser aleatórios e jamais reutilizados com
a mesma chave. Mascaramento é apenas apresentação e nunca substitui
criptografia.

## Particionamento mensal

As tabelas `purchase_order`, `inventory_movement`, `sales_transaction` e `audit_log` são particionadas por intervalo mensal. A instalação cria 19 meses por tabela: 12 anteriores, o atual e 6 futuros. A função `sp_create_monthly_partitions` deve ser executada mensalmente para manter a janela futura.

| Tabela | Chave de partição | Motivo |
|---|---|---|
| `purchase_order` | `order_date` | Consultas e fechamento por competência |
| `inventory_movement` | `movement_date` | Maior trilha operacional e consultas por período |
| `sales_transaction` | `sale_date` | Alto volume e relatórios/fechamentos mensais |
| `audit_log` | `operation_date` | Retenção e investigação por período |

O particionamento melhora poda de partições quando a consulta filtra a coluna temporal. Ele não substitui índices. Consultas da API devem sempre usar intervalos fechados/abertos, por exemplo `sale_date >= :inicio AND sale_date < :fim`.

## Relacionamentos centrais

```text
company 1---N retail_store 1---N employee 1---1 app_user
                                employee 1---1 employee_private_data
company 1---N product
retail_store 1---N inventory N---1 batch N---1 product
supplier 1---N purchase_order 1---N purchase_order_item N---1 product
purchase_order 1---N receiving 1---N receiving_item 1---N batch
sales_transaction 1---N sale_item N---1 product
sales_transaction 1---N sale_payment
customer 1---1 loyalty_account 1---N loyalty_transaction
customer 1---0..1 customer_private_data
alert 1---N suggested_action 1---N promotion
transfer 1---N transfer_item
donation 1---N donation_item
disposal 1---N disposal_item
```

## Rotas sugeridas para a API

| Recurso | Rotas principais | Tabelas |
|---|---|---|
| Autenticação e funcionários | `POST /auth/login`, `POST /auth/password-reset`, `GET/POST/PUT /employees` | `app_user`, `password_reset_token`, `employee`, `employee_private_data`, `employee_role` |
| Empresas e lojas | `GET/POST/PUT /companies`, `GET/POST/PUT /stores` | `company`, `retail_store`, `address` |
| Produtos | `GET/POST/PUT /products`, `GET /products/{id}/prices` | `product`, `product_category`, `tax_profile`, `store_product_price` |
| Fornecedores e compras | `GET/POST /suppliers`, `GET/POST /purchase-orders`, `POST /receivings` | `supplier`, `supplier_product`, `purchase_order*`, `receiving*` |
| Estoque | `GET /inventory`, `POST /inventory/movements`, `POST /inventory-counts` | `batch`, `inventory`, `inventory_movement`, `inventory_count*` |
| PDV | `POST /pos/shifts`, `POST /sales`, `POST /sales/{id}/cancel-requests` | `pos_*`, `sales_transaction`, `sale_item`, `sale_payment`, `fiscal_document` |
| Alertas e ações | `GET /alerts`, `POST /suggested-actions/{id}/decision` | `alert`, `suggested_action` |
| Promoções | `GET/POST /promotions`, `POST /promotions/{id}/approve` | `promotion`, `promotion_item` |
| Clientes e fidelidade | `POST /client/profile`, `GET/PUT /client/profile`, `POST /client/auth/login`, `POST /client/auth/recovery`, `GET /client/loyalty` | `customer*`, `loyalty_*`, funções `fn_api_*customer*` |
| Logística e perdas | `POST /transfers`, `POST /donations`, `POST /disposals`, `POST /replenishments` | `transfer*`, `donation*`, `disposal*`, `replenishment_*` |
| Monitoramento | `GET /system/events`, `POST /system/events/{id}/retry`, `GET /system/logs`, `GET /system/jobs` | `event_queue`, `system_log`, `error_log`, `job_log` |

As rotas de escrita devem usar transação, idempotency key e controle otimista por `version` quando disponível. Recursos particionados usam a data junto do ID em operações internas porque a PK inclui a chave de partição.

## Contrato de compatibilidade com a API

O módulo `25_api_rpa_compatibility.sql` materializa o contrato usado pela API
operacional. Ele adiciona exclusão lógica aos itens de contagem e de pedido,
vincula logs de job à empresa, completa os enums e oferece funções atômicas
para pedido, recebimento, estoque e idempotência.

| Objeto | Responsabilidade |
|---|---|
| `fn_find_outbox_event_by_key` | Recupera o evento já publicado para impedir a repetição de uma operação com a mesma chave. |
| `fn_api_insert_purchase_order` | Insere pedidos sem esconder a chave temporal da partição da API. |
| `fn_api_insert_receiving` | Insere o recebimento preservando a referência composta do pedido. |
| `fn_api_upsert_inventory` | Cria ou reativa o saldo único de loja, lote e tipo. |
| `fn_atomic_update_inventory` | Atualiza saldo, versão e razão de movimentos de forma atômica. |
| `vw_api_purchase_order*` | Expõe pedidos e itens, incluindo exclusão lógica. |
| `vw_api_receiving*` | Expõe recebimentos e seus itens com vínculo ao pedido. |
| `vw_api_store_product_price` | Expõe o preço vigente por loja e produto. |
| `vw_api_product*_history` | Expõe históricos protegidos pelo tenant do produto. |
| `vw_api_system_*` | Expõe eventos, logs e jobs apenas para a empresa autenticada. |

As views usam `security_invoker=true`. Portanto, as consultas continuam
submetidas ao RLS das tabelas de origem; uma view não amplia o tenant do
usuário. `job_log.company_id` é opcional somente para compatibilidade com
registros globais antigos. Esses registros com `NULL` não aparecem na API.

### Contrato da API mobile

O módulo `38_client_mobile_api.sql` separa o serviço mobile do cliente da API
operacional. O login técnico do backend recebe somente
`mottainai_client_api`; o aplicativo nunca conecta diretamente ao PostgreSQL.

| Objeto | Responsabilidade |
|---|---|
| `api_client_catalog_stores` | Lojas ativas e endereço operacional necessário para geofence. |
| `api_client_catalog_promotions` | Promoções aprovadas, vigentes e com item disponível. |
| `api_client_catalog_promotion_items` | Itens ativos de promoções elegíveis, sem dados internos. |
| `fn_api_reserve_customer_id` | Reserva o ID usado como AAD antes de cifrar o envelope. |
| `fn_api_create_firebase_customer_profile` | Cria cliente tokenizado, envelope e conta de fidelidade atomicamente. |
| `fn_api_update_firebase_customer_profile` | Atualiza tokens permitidos e substitui o envelope autenticado. |
| `fn_api_customer_login` | Confere BCrypt, contabiliza falhas e aplica bloqueio temporário. |
| `fn_api_request_customer_recovery` | Registra somente o BCrypt do segredo de recuperação por 15 minutos. |
| `fn_api_clear_customer_recovery` | Revoga o segredo quando a entrega externa falha. |
| `fn_api_validate_customer_recovery` | Valida segredo e expiração sem devolver hashes. |
| `fn_api_reset_customer_password` | Troca o BCrypt e consome o segredo em uma única operação. |
| `fn_api_bootstrap_legacy_customer_context` | Inicializa contexto de cliente legado pelo token de e-mail após JWT válido. |

## Segurança e LGPD

O banco usa defesa em profundidade. A role de grupo `mottainai_api` não possui
login, privilégios administrativos, capacidade de ignorar RLS ou permissão de
DDL. O login real da API deve receber essa role e executar `SET ROLE
mottainai_api` ao abrir a conexão.

| Camada | Controle aplicado |
|---|---|
| Identidade | Login do funcionário usa `firebase_uid`; senhas e códigos de recuperação usam BCrypt; tokens de sessão usam SHA-256 |
| Dados pessoais | Nome, CPF, e-mail e telefone do funcionário usam AES-256-GCM; documento de venda e identificadores não recuperáveis permanecem tokenizados |
| Chaves | Chaves AES ficam fora do banco, em KMS/secret manager, com menor privilégio, versão, auditoria e rotação |
| Cliente | `mottainai_customer_api` mantém compatibilidade; `mottainai_client_api` é o contrato isolado do backend mobile e não lê `customer_auth` diretamente |
| RPA | `legacy_sync_record` mantém correlação e SHA-256 do payload; `mottainai_migrator` limita o contexto de importação |
| Sessão | `staff_session` controla expiração, rotação, revogação, IP e dispositivo |
| Tenant | RLS limita empresa e loja; administrador acessa lojas da própria empresa e demais perfis somente sua loja |
| Contexto | Funções `SECURITY DEFINER` validam usuário, empresa e loja e usam parâmetros locais à transação |
| Antifraude de contexto | A API não pode executar o setter antigo, chamar `set_config` nem alterar diretamente os parâmetros `app.current_*` |
| Privilégios | API recebe apenas operações necessárias e não pode executar DDL, manutenção de partição ou alteração de auditoria |
| Instalação gerenciada | O migrator pode usar `CREATEROLE` sem `SUPERUSER`; atributos privilegiados existentes são verificados e exigem correção administrativa se estiverem ativos |
| Views | Views operacionais usam `security_invoker=true`; views mobile usam `security_barrier=true`, proprietário sem login e filtros explícitos de publicação |
| Auditoria | Eventos recebem empresa, loja, IP, aplicação e transação; hashes e CPF são removidos do JSON |
| Disponibilidade | A role da API possui limites de statement, lock e transação ociosa |
| CI | Instalação limpa, reaplicação, testes de segurança, varredura de segredos e lint SQL |

### Contrato obrigatório da API

Cada requisição autenticada deve executar dentro de uma transação. A API
valida a senha com BCrypt antes de inicializar o contexto no banco. O bootstrap
aceita somente `FIREBASE_UID`; e-mail e CPF não são identidades de autenticação.
Convites pendentes usam `fn_bootstrap_staff_context_by_token`. Nome, CPF e
contatos só podem ser abertos por serviço autorizado, que
lê o envelope e usa a chave externa ao PostgreSQL:

```sql
BEGIN;
SET LOCAL ROLE mottainai_api;
SELECT mottainai.fn_bootstrap_staff_context(:identity, :lookup);
-- consultas e comandos da requisição
COMMIT;
```

Para refresh ou recuperação, use respectivamente
`fn_bootstrap_staff_context_by_session` ou
`fn_bootstrap_staff_context_by_token`. Um retorno nulo ou falso encerra a
transação. Nunca devolva hashes, CPF integral, dados de outra empresa ou
conteúdo de auditoria sem autorização administrativa.

Para o aplicativo do cliente, o backend valida o token Firebase, calcula
`AUTH_SHA256_<64-hex>` e usa a role isolada do serviço mobile:

```sql
BEGIN;
SET LOCAL ROLE mottainai_client_api;
SELECT mottainai.fn_bootstrap_customer_context(:external_auth_token);
-- consultas permitidas do próprio cliente
COMMIT;
```

### Contrato obrigatório da RPA

A RPA executa cada empresa em uma transação e assume a role sem login
`mottainai_migrator`. O login técnico recebe a associação fora do script
versionado e nunca recebe `BYPASSRLS`, `SUPERUSER` ou `CREATEROLE`:

```sql
GRANT mottainai_migrator TO nome_real_do_login_da_rpa;

BEGIN;
SET LOCAL ROLE mottainai_migrator;
SELECT mottainai.fn_set_legacy_migration_context(:company_id);
-- upserts idempotentes da empresa atual
SELECT mottainai.fn_clear_legacy_migration_context();
COMMIT;
```

Durante `legacy-import`, a auditoria continua ativa. Ela grava a empresa,
identifica a aplicação como `legacy-import` e aceita `user_id = NULL` quando o
legado não possui uma conta operacional correspondente. Senhas sem BCrypt e
registros sem vínculo seguro continuam na quarentena da RPA.

### Responsabilidades de infraestrutura

- exigir TLS com validação do certificado;
- manter credenciais no secret manager do ambiente, nunca no repositório;
- usar BCrypt com custo revisado para senhas e códigos de recuperação;
- gerar tokens SHA-256 no backend e manter o segredo fora do banco;
- criptografar nome, CPF, e-mail e telefone de funcionário com AES-256-GCM no serviço autorizado;
- manter chaves no KMS/secret manager, registrar acessos e testar rotação e recuperação;
- ativar backups criptografados, recuperação ponto no tempo e teste periódico de restauração;
- monitorar tentativas de login, falhas de RLS, revogações e alterações de privilégio;
- manter logs sem senha, token, CPF integral ou payload pessoal desnecessário;
- definir retenção e anonimização conforme LGPD e obrigações fiscais.

## Instalação e manutenção

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_operational \
  -f database/operational/install.sql
```

O orquestrador `install.sql` deve ser executado pelo `psql`, pois usa o
metacomando `\ir` para carregar os módulos em relação ao próprio arquivo.
Em outra ferramenta de migração, configure a execução dos arquivos na mesma
ordem declarada pelo instalador.

Em bases existentes, execute os módulos incrementais na ordem
`10_product_company.sql`, `20_security_hardening.sql`,
`22_sensitive_data_contract.sql`, `24_jpa_compatibility.sql` e
`25_api_rpa_compatibility.sql`. Depois, a alteração de PII ocorre em duas
entregas independentes:

1. Execute `prepare_existing_reversible_pii.sql` para criar o cofre e marcar os
   registros legados como estado transitório.
2. Atualize API/RPA para criptografar valores vindos da fonte original com
   AES-256-GCM e preencher `employee_private_data`. Um SHA-256
   existente não pode ser descriptografado nem convertido em ciphertext.
3. Preencha `app_user.firebase_uid` para todas as contas ativas. Convites
   pendentes podem permanecer sem UID.
4. Execute `finalize_existing_reversible_pii.sql`. O preflight falha sem apagar
   nada se qualquer envelope ou UID estiver incompleto; somente então remove
   `employee.name/cpf/email/phone` e `app_user.cpf/email`.
5. Execute `update_existing_customer_private_data.sql` para aplicar a retenção
   lógica do envelope e o contrato da API mobile. A migration não inventa
   ciphertext a partir de SHA-256 e não cria login nem senha de ambiente.

Faça backup e teste restauração antes da finalização. Os arquivos
`11_product_company_tests.sql` e
`26_api_rpa_compatibility_tests.sql` pertencem ao CI e não fazem parte do
instalador de produção.

O script `20_security_hardening.sql` cria a role de grupo `mottainai_api` sem
login. Após a instalação, um administrador deve associar o login real do
Render sem colocar credenciais no SQL versionado:

```sql
GRANT mottainai_api TO nome_real_do_login_da_api;
GRANT mottainai_client_api TO nome_real_do_login_da_api_mobile;
```

O login mobile deve ser `NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
NOBYPASSRLS`. Guarde sua senha no secret manager e configure TLS. As roles
`mottainai_client_catalog_owner`, `mottainai_client_profile_owner` e
`mottainai_client_auth_owner` são proprietárias sem login e não podem ser
concedidas a usuários ou serviços.

O hardening de produto pressupõe a migration que adiciona
`product.company_id`. Em ambientes atualizados fora de ordem, reaplique
`20_security_hardening.sql` depois da migration de produto para conceder seus
privilégios protegidos por RLS.

Em uma base já existente, execute `10_product_company.sql`. A migration tenta
identificar a empresa pelos vínculos do produto com loja, estoque, compra,
venda, promoção e reposição. Se um produto estiver associado a mais de uma
empresa, ou não puder ser identificado em uma base com várias empresas, a
migration interrompe sem adivinhar o proprietário; nesse caso, faça o
mapeamento explícito e execute novamente.

Mensalmente, executar:

```sql
SELECT mottainai.sp_create_monthly_partitions(12, 6);
```

Antes de descartar partições antigas, validar retenção fiscal, auditoria, backup e carga confirmada no analítico.

## Dicionário de dados

O catálogo abaixo é gerado a partir dos scripts desta versão. “Relacionamentos” lista FKs locais; tabelas de arquivo repetem a estrutura de sua tabela de origem.

### `address`

**Por que existe:** Normaliza endereços reutilizados.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `address_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `zip_code` | `CHAR(8) NOT NULL CHECK (zip_code ~ '^\d{8}$')` | Atributo do domínio desta entidade. |
| `street` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `number` | `VARCHAR(10) NOT NULL` | Atributo do domínio desta entidade. |
| `complement` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `neighborhood` | `VARCHAR(100) NOT NULL` | Atributo do domínio desta entidade. |
| `city` | `VARCHAR(100) NOT NULL` | Atributo do domínio desta entidade. |
| `state` | `CHAR(2) NOT NULL CHECK (state ~ '^[A-Z]{2}$')` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `alert`

**Por que existe:** Registra risco ou exceção operacional.

**Relacionamentos:** retail_store(store_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `alert_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `title` | `VARCHAR(120) NOT NULL` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `alert_type` | `alert_type NOT NULL` | Atributo do domínio desta entidade. |
| `priority` | `priority_level NOT NULL DEFAULT 'MEDIUM'` | Atributo do domínio desta entidade. |
| `status` | `alert_status NOT NULL DEFAULT 'ACTIVE'` | Estado atual do ciclo de vida. |
| `generated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `resolved_at` | `TIMESTAMP` | Data e hora usada para auditoria ou processamento. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `app_user`

**Por que existe:** Mantém a conta de acesso vinculada ao funcionário.

**Relacionamentos:** employee(employee_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `user_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL UNIQUE REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `firebase_uid` | `VARCHAR(255) UNIQUE` | Identidade externa primária. É obrigatória para conta ativa e nula durante convite pendente. |
| `password_hash` | `VARCHAR(255) NOT NULL` | Hash criptográfico; o valor original não é persistido. |
| `password_set` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o funcionário já definiu a senha inicial. |
| `token_version` | `INTEGER NOT NULL DEFAULT 0` | Invalida sessões emitidas antes de uma alteração de segurança. |
| `last_login` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `audit_log`

**Por que existe:** Mantém trilha de auditoria.

**Relacionamentos:** app_user(user_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `audit_id` | `BIGINT GENERATED ALWAYS AS IDENTITY` | Identificador ou chave de correlação. |
| `table_affected` | `VARCHAR(60) NOT NULL` | Atributo do domínio desta entidade. |
| `operation` | `audit_operation NOT NULL` | Atributo do domínio desta entidade. |
| `record_id` | `TEXT NOT NULL` | Identificador ou chave de correlação. |
| `user_id` | `INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `old_data` | `JSONB` | Atributo do domínio desta entidade. |
| `new_data` | `JSONB` | Atributo do domínio desta entidade. |
| `operation_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `company_id` | `INTEGER` | Empresa do contexto que originou a operação. |
| `store_id` | `INTEGER` | Loja do contexto que originou a operação. |
| `client_ip` | `INET` | Endereço de origem observado pelo PostgreSQL. |
| `application_name` | `VARCHAR(100)` | Aplicação cliente declarada na conexão. |
| `transaction_id` | `BIGINT` | Identificador da transação para correlação forense. |

### `audit_log_archive`

**Por que existe:** Arquiva auditoria fora da janela ativa.

**Relacionamentos:** LIKE audit_log.

| Campo | Definição SQL | Uso |
|---|---|---|

### `batch`

**Por que existe:** Rastreia lote, validade e custo.

**Relacionamentos:** product(product_id), receiving_item(receiving_item_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `batch_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `receiving_item_id` | `INTEGER REFERENCES receiving_item(receiving_item_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `batch_code` | `VARCHAR(60) NOT NULL UNIQUE` | Atributo do domínio desta entidade. |
| `manufacture_date` | `DATE` | Data de negócio e possível filtro temporal. |
| `expiration_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `initial_quantity` | `DECIMAL(10,3) NOT NULL CHECK (initial_quantity > 0)` | Quantidade ou contagem mensurável. |
| `unit_cost` | `DECIMAL(10,2) NOT NULL CHECK (unit_cost >= 0)` | Valor monetário ou medida financeira. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `version` | `INTEGER DEFAULT 1` | Versão para evolução ou concorrência otimista. |

### `company`

**Por que existe:** Representa o tenant/empresa contratante.

**Relacionamentos:** subscription_plan(plan_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `company_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `plan_id` | `INTEGER NOT NULL REFERENCES subscription_plan(plan_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `official_name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `trade_name` | `VARCHAR(150)` | Atributo do domínio desta entidade. |
| `cnpj` | `CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj))` | Atributo do domínio desta entidade. |
| `email` | `VARCHAR(150) NOT NULL CHECK (fn_validate_email(email))` | Endereço eletrônico sujeito a validação e controle de acesso. |
| `phone` | `VARCHAR(20)` | Atributo do domínio desta entidade. |
| `latitude` | `DECIMAL(9,6) CHECK (latitude BETWEEN -90 AND 90)` | Atributo do domínio desta entidade. |
| `longitude` | `DECIMAL(9,6) CHECK (longitude BETWEEN -180 AND 180)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `customer`

**Por que existe:** Cadastra o cliente do aplicativo.

**Relacionamentos:** possui relacionamento lógico com fidelidade, consentimento
e geofence. `address_id` é mantido apenas por compatibilidade estrutural e deve
permanecer nulo para clientes.

| Campo | Definição SQL | Uso |
|---|---|---|
| `customer_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `full_name` | `VARCHAR(150) NOT NULL` | Token `CUS_SHA256_<64-hex>`; nunca contém o nome original. |
| `cpf` | `VARCHAR(80) UNIQUE` | Token `CPF_SHA256_<64-hex>`; nunca contém o CPF original. |
| `email` | `VARCHAR(150)` | Token `EMAIL_SHA256_<64-hex>`. |
| `phone` | `VARCHAR(80)` | Token `PHONE_SHA256_<64-hex>`. |
| `address_id` | `INTEGER` | Compatibilidade; constraint exige valor nulo para cliente. |
| `external_auth_uid` | `VARCHAR(150) UNIQUE` | Token `AUTH_SHA256_<64-hex>` do subject Firebase. |
| `birth_year` | `SMALLINT` | Minimização da data de nascimento para o ano. |
| `address_token` | `VARCHAR(80)` | Token SHA-256 do endereço residencial, quando necessário. |
| `data_protection_version` | `SMALLINT NOT NULL DEFAULT 1` | Versão do contrato de tratamento aplicado pelo backend. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `marketing_consent` | `BOOLEAN NOT NULL DEFAULT FALSE` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `customer_private_data`

**Por que existe:** Guarda, de forma opcional e recuperável, os dados pessoais
originais do cliente que a aplicação esteja autorizada a tratar. Os tokens de
`customer` e `customer_auth` continuam sendo usados para buscas e unicidade.

**Relacionamentos:** customer(customer_id) com `ON DELETE RESTRICT`. A remoção
é lógica para preservar evidência e evitar destruição acidental do ciphertext.

| Campo | Definição SQL | Uso |
|---|---|---|
| `customer_id` | `INTEGER PRIMARY KEY REFERENCES customer(customer_id) ON DELETE RESTRICT` | Garante no máximo um envelope por cliente. |
| `payload_ciphertext` | `BYTEA NOT NULL` | JSON_V1 cifrado com AES-256-GCM e tag de autenticação. |
| `payload_nonce` | `BYTEA NOT NULL` com 12 bytes | Nonce exclusivo; nunca pode ser reutilizado com a mesma chave. |
| `key_version` | `SMALLINT NOT NULL` positivo | Versão da chave mantida no KMS externo. |
| `algorithm` | `VARCHAR(20) DEFAULT 'AES-256-GCM'` | Algoritmo permitido pelo contrato. |
| `payload_format` | `VARCHAR(20) DEFAULT 'JSON_V1'` | Versão do conteúdo cifrado interpretada pela API. |
| `encrypted_at` | `TIMESTAMPTZ NOT NULL` | Momento de geração do envelope atual. |
| `created_at`, `updated_at` | `TIMESTAMPTZ NOT NULL` | Auditoria temporal sem expor o conteúdo. |
| `deleted_at` | `TIMESTAMPTZ` | Retirada lógica; bloqueia as leituras normais sem apagar o envelope. |

A tabela força RLS. `mottainai_customer_api` e `mottainai_client_api`, após o
bootstrap, leem apenas o envelope do próprio cliente. Inserções e substituições
do envelope mobile ocorrem por funções `SECURITY DEFINER` pertencentes a uma
role sem login. `mottainai_api` pode ler somente quando o funcionário ativo tem
nível de gerente/administrador e existe venda válida do cliente na mesma
empresa; sua única escrita direta é `deleted_at`. Não há `DELETE` físico para
as APIs. Ciphertext/nonce são redigidos da auditoria e excluídos do analítico.
A chave AES nunca é armazenada no PostgreSQL.

### `customer_auth`

**Por que existe:** Controla autenticação e bloqueio do cliente.

**Relacionamentos:** customer(customer_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `customer_auth_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `customer_id` | `INTEGER NOT NULL UNIQUE REFERENCES customer(customer_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `login_email` | `VARCHAR(150) NOT NULL UNIQUE` | Token `EMAIL_SHA256_<64-hex>`. |
| `password_hash` | `TEXT NOT NULL` | BCrypt; o valor original nunca é persistido. |
| `password_changed_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `failed_attempts` | `INTEGER NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0)` | Atributo do domínio desta entidade. |
| `locked_until` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `recovery_token_hash` | `TEXT` | BCrypt do código de recuperação de baixa entropia. |
| `recovery_expires_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `last_login_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `customer_consent`

**Por que existe:** Mantém evidência versionada de concessão e retirada de
consentimento, sem copiar dados pessoais.

**Relacionamentos:** customer(customer_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `customer_consent_id` | `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador do evento de consentimento. |
| `customer_id` | `INTEGER NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE` | Cliente proprietário do consentimento. |
| `consent_type` | `VARCHAR(40) NOT NULL` | Política, marketing, geolocalização ou fidelidade. |
| `granted` | `BOOLEAN NOT NULL` | Indica concessão ou retirada. |
| `policy_version` | `VARCHAR(40) NOT NULL` | Versão exata do texto aceito. |
| `collection_channel` | `VARCHAR(30) NOT NULL` | Canal em que a decisão foi registrada. |
| `recorded_at` | `TIMESTAMPTZ NOT NULL` | Momento da manifestação. |
| `withdrawn_at` | `TIMESTAMPTZ` | Momento obrigatório para uma retirada. |

### `customer_geofence`

**Por que existe:** Relaciona cliente e loja para avisos de proximidade.

**Relacionamentos:** customer(customer_id), retail_store(store_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `geofence_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `customer_id` | `INTEGER NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `radius_meters` | `INTEGER NOT NULL DEFAULT 1000 CHECK (radius_meters BETWEEN 50 AND 10000)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `disposal`

**Por que existe:** Controla descarte e motivo da perda.

**Relacionamentos:** employee(employee_id), retail_store(store_id), suggested_action(suggested_action_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `disposal_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `suggested_action_id` | `INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `reason` | `VARCHAR(100) NOT NULL` | Atributo do domínio desta entidade. |
| `disposal_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `version` | `INTEGER DEFAULT 1` | Versão para evolução ou concorrência otimista. |

### `disposal_item`

**Por que existe:** Detalha lotes descartados.

**Relacionamentos:** batch(batch_id), disposal(disposal_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `disposal_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `disposal_id` | `INTEGER NOT NULL REFERENCES disposal(disposal_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `batch_id` | `INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `disposed_quantity` | `DECIMAL(10,3) NOT NULL CHECK (disposed_quantity > 0)` | Quantidade ou contagem mensurável. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `donation`

**Por que existe:** Controla doação de produtos.

**Relacionamentos:** employee(employee_id), retail_store(store_id), suggested_action(suggested_action_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `donation_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `suggested_action_id` | `INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `institution` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `donation_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `status` | `donation_status NOT NULL DEFAULT 'REGISTERED'` | Estado atual do ciclo de vida. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `version` | `INTEGER DEFAULT 1` | Versão para evolução ou concorrência otimista. |

### `donation_item`

**Por que existe:** Detalha lotes doados.

**Relacionamentos:** batch(batch_id), donation(donation_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `donation_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `donation_id` | `INTEGER NOT NULL REFERENCES donation(donation_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `batch_id` | `INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `donated_quantity` | `DECIMAL(10,3) NOT NULL CHECK (donated_quantity > 0)` | Quantidade ou contagem mensurável. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `employee`

**Por que existe:** Mantém somente o vínculo operacional do funcionário com loja, papel e ciclo de vida.

**Relacionamentos:** employee_role(role_id), retail_store(store_id), employee_private_data(employee_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `employee_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `role_id` | `INTEGER NOT NULL REFERENCES employee_role(role_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `hire_date` | `DATE NOT NULL DEFAULT CURRENT_DATE` | Data de negócio e possível filtro temporal. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `employee_private_data`

**Por que existe:** Isola nome, CPF e contatos do funcionário em um cofre lógico 1:1,
com criptografia reversível autenticada e apresentação mascarada.
A tabela é excluída integralmente do ETL analítico.

**Relacionamentos:** employee(employee_id) com `ON DELETE CASCADE`.

| Campo | Definição SQL | Uso |
|---|---|---|
| `employee_id` | `INTEGER PRIMARY KEY REFERENCES employee(employee_id) ON DELETE CASCADE` | Identifica o proprietário do envelope sem duplicar identidade. |
| `name_ciphertext`, `cpf_ciphertext`, `email_ciphertext`, `phone_ciphertext` | `BYTEA` | Ciphertext AES-256-GCM com tag de autenticação; não é texto codificado nem hash. |
| `name_nonce`, `cpf_nonce`, `email_nonce`, `phone_nonce` | `BYTEA` com 12 bytes | Nonce exclusivo para cada criptografia AES-GCM. |
| `name_masked`, `cpf_masked`, `email_masked`, `phone_masked` | `VARCHAR` | Valor seguro para telas; nunca serve como fonte para descriptografia. |
| `key_version` | `SMALLINT` positivo | Versão da chave externa necessária para rotação e descriptografia. |
| `algorithm` | `VARCHAR(20) DEFAULT 'AES-256-GCM'` | Algoritmo obrigatório do envelope. |
| `protection_state` | `VARCHAR(20)` | `MIGRATION_PENDING` durante backfill ou `ENCRYPTED` quando completo. |
| `encrypted_at` | `TIMESTAMPTZ` | Momento em que o serviço gerou o envelope atual. |
| `created_at`, `updated_at` | `TIMESTAMPTZ` | Auditoria temporal do registro protegido. |

### `employee_role`

**Por que existe:** Define papéis e níveis de permissão.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `role_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(80) NOT NULL UNIQUE` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `permission_level` | `INTEGER NOT NULL CHECK (permission_level >= 0)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `error_log`

**Por que existe:** Registra erros tratados.

**Relacionamentos:** app_user(user_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `error_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `error_code` | `VARCHAR(20)` | Atributo do domínio desta entidade. |
| `error_message` | `TEXT NOT NULL` | Atributo do domínio desta entidade. |
| `function_name` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `parameters` | `JSONB` | Atributo do domínio desta entidade. |
| `stack_trace` | `TEXT` | Atributo do domínio desta entidade. |
| `user_id` | `INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `event_queue`

**Por que existe:** Implementa o outbox transacional.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `event_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `event_type` | `VARCHAR(50) NOT NULL` | Atributo do domínio desta entidade. |
| `event_data` | `JSONB NOT NULL` | Atributo do domínio desta entidade. |
| `priority` | `INTEGER DEFAULT 5` | Atributo do domínio desta entidade. |
| `status` | `event_status NOT NULL DEFAULT 'PENDING'` | Estado atual do ciclo de vida. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `processed_at` | `TIMESTAMP` | Data e hora usada para auditoria ou processamento. |
| `retry_count` | `INTEGER DEFAULT 0` | Quantidade ou contagem mensurável. |
| `error_message` | `TEXT` | Atributo do domínio desta entidade. |
| `event_uuid` | `UUID NOT NULL DEFAULT gen_random_uuid()` | Chave global e idempotente do evento. |
| `aggregate_type` | `VARCHAR(60)` | Tipo do agregado que originou o evento. |
| `aggregate_id` | `VARCHAR(120)` | Identificador simples ou composto do agregado. |
| `company_id` | `INTEGER` | Empresa relacionada ao evento. |
| `store_id` | `INTEGER` | Loja relacionada ao evento. |
| `schema_version` | `INTEGER NOT NULL DEFAULT 1` | Versão do contrato do payload. |
| `occurred_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Instante em que o fato ocorreu. |
| `published_at` | `TIMESTAMPTZ` | Instante de confirmação da publicação. |
| `idempotency_key` | `VARCHAR(180)` | Chave única para impedir publicação duplicada. |

### `fiscal_document`

**Por que existe:** Relaciona o documento fiscal à venda.

**Relacionamentos:** sales_transaction(sale_id, sale_date).

| Campo | Definição SQL | Uso |
|---|---|---|
| `fiscal_document_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `sale_id` | `INTEGER NOT NULL` | Identificador ou chave de correlação. |
| `sale_date` | `TIMESTAMP NOT NULL` | Data de negócio e possível filtro temporal. |
| `document_type` | `VARCHAR(10) NOT NULL CHECK (document_type IN ('NFE','NFCE','SAT'))` | Atributo do domínio desta entidade. |
| `series` | `VARCHAR(10)` | Atributo do domínio desta entidade. |
| `document_number` | `VARCHAR(30)` | Atributo do domínio desta entidade. |
| `access_key` | `VARCHAR(44) UNIQUE CHECK (access_key IS NULL OR access_key ~ '^\d{44}$')` | Atributo do domínio desta entidade. |
| `status` | `VARCHAR(20) NOT NULL DEFAULT 'AUTHORIZED'` | Estado atual do ciclo de vida. |
| `issued_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `total_amount` | `DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0)` | Valor monetário ou medida financeira. |
| `protocol_number` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `xml_content` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `integration_log`

**Por que existe:** Registra comunicação com integrações.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `integration_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `integration_type` | `VARCHAR(50) NOT NULL` | Atributo do domínio desta entidade. |
| `direction` | `VARCHAR(10) NOT NULL` | Atributo do domínio desta entidade. |
| `payload` | `JSONB` | Atributo do domínio desta entidade. |
| `response` | `JSONB` | Atributo do domínio desta entidade. |
| `status` | `VARCHAR(20) NOT NULL` | Estado atual do ciclo de vida. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `inventory`

**Por que existe:** Mantém o saldo por loja, lote e tipo.

**Relacionamentos:** batch(batch_id), retail_store(store_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `inventory_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `batch_id` | `INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `inventory_type` | `inventory_type NOT NULL DEFAULT 'NORMAL'` | Atributo do domínio desta entidade. |
| `current_quantity` | `DECIMAL(10,3) NOT NULL DEFAULT 0 CHECK (current_quantity >= 0)` | Quantidade ou contagem mensurável. |
| `minimum_quantity` | `DECIMAL(10,3) NOT NULL DEFAULT 0 CHECK (minimum_quantity >= 0)` | Quantidade ou contagem mensurável. |
| `maximum_quantity` | `DECIMAL(10,3) CHECK (maximum_quantity IS NULL OR maximum_quantity >= minimum_quantity)` | Quantidade ou contagem mensurável. |
| `location` | `VARCHAR(80)` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `version` | `INTEGER DEFAULT 1` | Versão para evolução ou concorrência otimista. |

### `inventory_count`

**Por que existe:** Representa uma contagem física.

**Relacionamentos:** employee(employee_id), retail_store(store_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `inventory_count_id` | `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `started_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Data e hora usada para auditoria ou processamento. |
| `finished_at` | `TIMESTAMPTZ` | Data e hora usada para auditoria ou processamento. |
| `status` | `inventory_status NOT NULL DEFAULT 'IN_PROGRESS'` | Estado atual do ciclo de vida. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Data e hora usada para auditoria ou processamento. |

### `inventory_count_item`

**Por que existe:** Compara saldo do sistema e quantidade contada.

**Relacionamentos:** inventory_count(inventory_count_id), inventory(inventory_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `inventory_count_item_id` | `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `inventory_count_id` | `BIGINT NOT NULL REFERENCES inventory_count(inventory_count_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `inventory_id` | `INTEGER NOT NULL REFERENCES inventory(inventory_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `system_quantity` | `DECIMAL(12,3) NOT NULL CHECK (system_quantity >= 0)` | Quantidade ou contagem mensurável. |
| `counted_quantity` | `DECIMAL(12,3) NOT NULL CHECK (counted_quantity >= 0)` | Quantidade ou contagem mensurável. |
| `difference` | `DECIMAL(12,3) GENERATED ALWAYS AS (counted_quantity - system_quantity) STORED` | Atributo do domínio desta entidade. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMPTZ` | Exclusão lógica; itens apagados podem ser reativados sem violar a unicidade da contagem. |

### `inventory_movement`

**Por que existe:** Registra o razão imutável do estoque.

**Relacionamentos:** employee(employee_id), inventory(inventory_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `movement_id` | `INTEGER GENERATED ALWAYS AS IDENTITY` | Identificador ou chave de correlação. |
| `inventory_id` | `INTEGER NOT NULL REFERENCES inventory(inventory_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `movement_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `movement_type` | `movement_type NOT NULL` | Atributo do domínio desta entidade. |
| `moved_quantity` | `DECIMAL(10,3) NOT NULL CHECK (moved_quantity <> 0)` | Quantidade ou contagem mensurável. |
| `previous_balance` | `DECIMAL(10,3) NOT NULL CHECK (previous_balance >= 0)` | Atributo do domínio desta entidade. |
| `current_balance` | `DECIMAL(10,3) NOT NULL CHECK (current_balance >= 0)` | Atributo do domínio desta entidade. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `store_id` | `INTEGER` | Identificador ou chave de correlação. |

### `inventory_movement_archive`

**Por que existe:** Arquiva movimentos de estoque.

**Relacionamentos:** LIKE inventory_movement.

| Campo | Definição SQL | Uso |
|---|---|---|

### `job_log`

**Por que existe:** Registra execução de rotinas.

**Relacionamentos:** company(company_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `job_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `company_id` | `INTEGER REFERENCES company(company_id) ON DELETE RESTRICT` | Empresa proprietária do job; registros legados globais podem permanecer nulos e ficam ocultos da API. |
| `job_name` | `VARCHAR(100) NOT NULL` | Atributo do domínio desta entidade. |
| `job_type` | `VARCHAR(50)` | Atributo do domínio desta entidade. |
| `start_time` | `TIMESTAMP NOT NULL` | Atributo do domínio desta entidade. |
| `end_time` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `duration_seconds` | `INTEGER` | Atributo do domínio desta entidade. |
| `records_processed` | `INTEGER` | Atributo do domínio desta entidade. |
| `success` | `BOOLEAN` | Atributo do domínio desta entidade. |
| `details` | `JSONB` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `legacy_sync_record`

**Por que existe:** Permite ao RPA repetir ou auditar a transferência entre os
dois PostgreSQL físicos sem duplicar registros e sem guardar o payload pessoal.

**Relacionamentos:** usa identificadores externos textuais para não criar FK
entre bancos físicos independentes.

| Campo | Definição SQL | Uso |
|---|---|---|
| `legacy_sync_id` | `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador local da sincronização. |
| `source_system` | `VARCHAR(40) NOT NULL` | Banco físico de origem. |
| `source_table` | `VARCHAR(80) NOT NULL` | Tabela legada de origem. |
| `source_record_id` | `VARCHAR(120) NOT NULL` | Chave idempotente do registro de origem. |
| `target_table` | `VARCHAR(80) NOT NULL` | Tabela operacional receptora. |
| `target_record_id` | `VARCHAR(120) NOT NULL` | Chave criada ou atualizada no operacional. |
| `payload_sha256` | `CHAR(64) NOT NULL` | SHA-256 do payload tratado para detectar alterações. |
| `sync_status` | `VARCHAR(20) NOT NULL` | Estado da aplicação ou repetição. |
| `synchronized_at` | `TIMESTAMPTZ NOT NULL` | Data da sincronização. |
| `error_code` | `VARCHAR(40)` | Código técnico sem payload ou informação pessoal. |

### `loyalty_account`

**Por que existe:** Mantém a conta e o saldo de pontos.

**Relacionamentos:** customer(customer_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `loyalty_account_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `customer_id` | `INTEGER NOT NULL UNIQUE REFERENCES customer(customer_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `points_balance` | `INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0)` | Atributo do domínio desta entidade. |
| `joined_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `loyalty_redemption`

**Por que existe:** Registra resgates de recompensa.

**Relacionamentos:** loyalty_account(loyalty_account_id), loyalty_reward(reward_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `redemption_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `loyalty_account_id` | `INTEGER NOT NULL REFERENCES loyalty_account(loyalty_account_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `reward_id` | `INTEGER NOT NULL REFERENCES loyalty_reward(reward_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `points_spent` | `INTEGER NOT NULL CHECK (points_spent > 0)` | Atributo do domínio desta entidade. |
| `redeemed_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `status` | `VARCHAR(20) NOT NULL DEFAULT 'CONFIRMED'` | Estado atual do ciclo de vida. |

### `loyalty_reward`

**Por que existe:** Define recompensas disponíveis.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `reward_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(120) NOT NULL` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `points_cost` | `INTEGER NOT NULL CHECK (points_cost > 0)` | Valor monetário ou medida financeira. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `valid_from` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `valid_until` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `loyalty_transaction`

**Por que existe:** Registra o razão de pontos.

**Relacionamentos:** loyalty_account(loyalty_account_id), sales_transaction(sale_id, sale_date).

| Campo | Definição SQL | Uso |
|---|---|---|
| `loyalty_transaction_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `loyalty_account_id` | `INTEGER NOT NULL REFERENCES loyalty_account(loyalty_account_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `sale_id` | `INTEGER` | Identificador ou chave de correlação. |
| `sale_date` | `TIMESTAMP` | Data de negócio e possível filtro temporal. |
| `transaction_type` | `VARCHAR(20) NOT NULL CHECK (transaction_type IN ('EARN','REDEEM','ADJUSTMENT','EXPIRE'))` | Atributo do domínio desta entidade. |
| `points` | `INTEGER NOT NULL CHECK (points <> 0)` | Atributo do domínio desta entidade. |
| `description` | `VARCHAR(255) NOT NULL` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `password_reset_token`

**Por que existe:** Controla recuperação de acesso por token com hash.

**Relacionamentos:** app_user(user_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `recovery_token_id` | `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `user_id` | `INTEGER NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `token_hash` | `TEXT NOT NULL UNIQUE` | BCrypt para recuperação de senha; SHA-256 para convite de alta entropia. |
| `token_type` | `VARCHAR(30) NOT NULL DEFAULT 'PASSWORD_RESET'` | Finalidade: recuperação de senha ou convite de funcionário. |
| `expires_at` | `TIMESTAMPTZ NOT NULL` | Atributo do domínio desta entidade. |
| `used_at` | `TIMESTAMPTZ` | Atributo do domínio desta entidade. |
| `requested_ip` | `INET` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Data e hora usada para auditoria ou processamento. |

### `staff_session`

**Por que existe:** Mantém sessões de funcionários por dispositivo, possibilitando rotação de refresh token, logout, revogação por troca de senha e investigação de acesso sem armazenar o token original.

**Relacionamentos:** app_user(user_id). Um usuário possui zero ou várias sessões.

| Campo | Definição SQL | Uso |
|---|---|---|
| `session_id` | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | Identificador imprevisível da sessão. |
| `user_id` | `INTEGER NOT NULL REFERENCES app_user(user_id) ON DELETE RESTRICT` | Usuário proprietário da sessão. |
| `refresh_token_hash` | `TEXT NOT NULL UNIQUE` | SHA-256 hexadecimal do refresh token de alta entropia. |
| `refresh_expires_at` | `TIMESTAMPTZ NOT NULL` | Limite absoluto de validade da sessão. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Início da sessão. |
| `last_used_at` | `TIMESTAMPTZ` | Última rotação ou utilização confirmada. |
| `revoked_at` | `TIMESTAMPTZ` | Momento do logout ou revogação administrativa. |
| `revoked_reason` | `VARCHAR(80)` | Motivo rastreável da revogação. |
| `ip_address` | `INET` | IP observado na criação ou renovação. |
| `user_agent` | `VARCHAR(500)` | Identificação limitada do dispositivo cliente. |

### `pos_cancel_request`

**Por que existe:** Controla aprovação de cancelamentos.

**Relacionamentos:** employee(employee_id), sale_item(sale_item_id), sales_transaction(sale_id, sale_date).

| Campo | Definição SQL | Uso |
|---|---|---|
| `cancel_request_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `sale_id` | `INTEGER NOT NULL` | Identificador ou chave de correlação. |
| `sale_date` | `TIMESTAMP NOT NULL` | Data de negócio e possível filtro temporal. |
| `sale_item_id` | `INTEGER REFERENCES sale_item(sale_item_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `requested_by` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Atributo do domínio desta entidade. |
| `approved_by` | `INTEGER REFERENCES employee(employee_id) ON DELETE RESTRICT` | Atributo do domínio desta entidade. |
| `target_type` | `pos_cancel_target NOT NULL` | Atributo do domínio desta entidade. |
| `reason` | `VARCHAR(250) NOT NULL` | Atributo do domínio desta entidade. |
| `status` | `pos_cancel_status NOT NULL DEFAULT 'PENDING'` | Estado atual do ciclo de vida. |
| `requested_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `decided_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `executed_at` | `TIMESTAMP` | Data e hora usada para auditoria ou processamento. |
| `decision_observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `pos_cash_movement`

**Por que existe:** Registra sangria e suprimento.

**Relacionamentos:** employee(employee_id), pos_shift(shift_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `cash_movement_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `shift_id` | `INTEGER NOT NULL REFERENCES pos_shift(shift_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `movement_type` | `VARCHAR(12) NOT NULL CHECK (movement_type IN ('SANGRIA','SUPRIMENTO'))` | Atributo do domínio desta entidade. |
| `amount` | `DECIMAL(12,2) NOT NULL CHECK (amount > 0)` | Valor monetário ou medida financeira. |
| `movement_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `reason` | `VARCHAR(200) NOT NULL` | Atributo do domínio desta entidade. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `pos_shift`

**Por que existe:** Controla abertura e fechamento do caixa.

**Relacionamentos:** employee(employee_id), pos_terminal(terminal_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `shift_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `terminal_id` | `INTEGER NOT NULL REFERENCES pos_terminal(terminal_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `opened_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `opening_amount` | `DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (opening_amount >= 0)` | Valor monetário ou medida financeira. |
| `closed_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `closing_amount` | `DECIMAL(12,2) CHECK (closing_amount IS NULL OR closing_amount >= 0)` | Valor monetário ou medida financeira. |
| `expected_amount` | `DECIMAL(12,2)` | Valor monetário ou medida financeira. |
| `status` | `VARCHAR(20) NOT NULL DEFAULT 'OPEN'` | Estado atual do ciclo de vida. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `pos_terminal`

**Por que existe:** Identifica o terminal de caixa.

**Relacionamentos:** retail_store(store_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `terminal_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `terminal_code` | `VARCHAR(30) NOT NULL` | Atributo do domínio desta entidade. |
| `name` | `VARCHAR(80) NOT NULL` | Atributo do domínio desta entidade. |
| `hostname` | `VARCHAR(120)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `product`

**Por que existe:** Mantém o cadastro mestre do SKU dentro da empresa proprietária. A empresa é a fronteira de isolamento do catálogo: uma empresa possui vários produtos e cada produto pertence obrigatoriamente a uma única empresa.

**Relacionamentos:** company(company_id), product_category(category_id), tax_profile(tax_profile_id). A exclusão da empresa é restrita enquanto houver produtos associados.

**Isolamento e unicidade:** a política RLS `product_policy` permite leitura e escrita somente quando `product.company_id` coincide com `app.current_company_id`. SKU e código de barras são únicos dentro de cada empresa, permitindo que empresas diferentes cadastrem os mesmos valores.

| Campo | Definição SQL | Uso |
|---|---|---|
| `product_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `company_id` | `INTEGER NOT NULL REFERENCES company(company_id) ON DELETE RESTRICT` | Empresa proprietária do produto e chave de isolamento multiempresa. |
| `category_id` | `INTEGER NOT NULL REFERENCES product_category(category_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `tax_profile_id` | `INTEGER NOT NULL REFERENCES tax_profile(tax_profile_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `sku` | `VARCHAR(50) NOT NULL` | Identificador interno único por empresa por meio de `UNIQUE (company_id, sku)`. |
| `barcode` | `VARCHAR(30) NOT NULL` | Código de barras único por empresa por meio de `UNIQUE (company_id, barcode)`. |
| `ncm` | `VARCHAR(8) NOT NULL CHECK (ncm ~ '^\d{8}$')` | Atributo do domínio desta entidade. |
| `cest` | `VARCHAR(7) CHECK (cest IS NULL OR cest ~ '^\d{7}$')` | Atributo do domínio desta entidade. |
| `name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `brand` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `unit_measure` | `VARCHAR(20) NOT NULL` | Atributo do domínio desta entidade. |
| `weight` | `DECIMAL(10,3) CHECK (weight >= 0)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `version` | `INTEGER NOT NULL DEFAULT 1` | Versão para evolução ou concorrência otimista. |
| `avg_cost` | `DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (avg_cost >= 0)` | Valor monetário ou medida financeira. |
| `suggested_price` | `DECIMAL(10,2) CHECK (suggested_price IS NULL OR suggested_price >= 0)` | Valor monetário ou medida financeira. |
| `base_price` | `DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (base_price >= 0)` | Preço-base exigido pelo contrato da API. |

### `product_category`

**Por que existe:** Classifica produtos.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `category_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(100) NOT NULL UNIQUE` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `product_history`

**Por que existe:** Preserva alterações do produto.

**Relacionamentos:** app_user(user_id), product(product_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `history_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER REFERENCES product(product_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `field_name` | `VARCHAR(50) NOT NULL` | Atributo do domínio desta entidade. |
| `old_value` | `TEXT` | Valor monetário ou medida financeira. |
| `new_value` | `TEXT` | Valor monetário ou medida financeira. |
| `changed_by` | `INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL` | Atributo do domínio desta entidade. |
| `changed_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |

### `product_price_history`

**Por que existe:** Preserva alterações de preço.

**Relacionamentos:** app_user(user_id), product(product_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `price_history_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER REFERENCES product(product_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `old_price` | `DECIMAL(10,2)` | Valor monetário ou medida financeira. |
| `new_price` | `DECIMAL(10,2)` | Valor monetário ou medida financeira. |
| `changed_by` | `INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL` | Atributo do domínio desta entidade. |
| `changed_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |

### `promotion`

**Por que existe:** Controla promoção, vigência e aprovação.

**Relacionamentos:** employee(employee_id), retail_store(store_id), suggested_action(suggested_action_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `promotion_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `suggested_action_id` | `INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `promotion_type` | `VARCHAR(20) NOT NULL CHECK (promotion_type IN ('DISCOUNT_PERCENT','DISCOUNT_FIXED','SPECIAL_PRICE'))` | Atributo do domínio desta entidade. |
| `starts_at` | `TIMESTAMP NOT NULL` | Atributo do domínio desta entidade. |
| `ends_at` | `TIMESTAMP NOT NULL` | Atributo do domínio desta entidade. |
| `status` | `promotion_status NOT NULL DEFAULT 'PENDING_APPROVAL'` | Estado atual do ciclo de vida. |
| `active` | `BOOLEAN NOT NULL DEFAULT FALSE` | Indica se o registro pode ser utilizado. |
| `created_by` | `INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL` | Atributo do domínio desta entidade. |
| `approved_by` | `INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL` | Atributo do domínio desta entidade. |
| `approved_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `promotion_item`

**Por que existe:** Relaciona produtos e preços promocionais.

**Relacionamentos:** product(product_id), promotion(promotion_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `promotion_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `promotion_id` | `INTEGER NOT NULL REFERENCES promotion(promotion_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `original_price` | `DECIMAL(12,2) NOT NULL CHECK (original_price >= 0)` | Valor monetário ou medida financeira. |
| `promotional_price` | `DECIMAL(12,2) NOT NULL CHECK (promotional_price >= 0)` | Valor monetário ou medida financeira. |
| `discount_percent` | `DECIMAL(7,4) GENERATED ALWAYS AS (` | Quantidade ou contagem mensurável. |
| `quantity_available` | `DECIMAL(12,3) CHECK (quantity_available IS NULL OR quantity_available >= 0)` | Quantidade ou contagem mensurável. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `purchase_order`

**Por que existe:** Registra o pedido de compra.

**Relacionamentos:** employee(employee_id), retail_store(store_id), supplier(supplier_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `purchase_order_id` | `INTEGER GENERATED ALWAYS AS IDENTITY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `supplier_id` | `INTEGER NOT NULL REFERENCES supplier(supplier_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `order_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `expected_delivery_date` | `DATE` | Data de negócio e possível filtro temporal. |
| `status` | `purchase_order_status NOT NULL DEFAULT 'PENDING'` | Estado atual do ciclo de vida. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `total_amount` | `DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0)` | Valor monetário ou medida financeira. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `version` | `INTEGER DEFAULT 1` | Versão para evolução ou concorrência otimista. |

### `purchase_order_item`

**Por que existe:** Detalha produtos do pedido.

**Relacionamentos:** product(product_id), purchase_order(purchase_order_id, order_date).

| Campo | Definição SQL | Uso |
|---|---|---|
| `purchase_order_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `purchase_order_id` | `INTEGER NOT NULL` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `requested_quantity` | `DECIMAL(10,3) NOT NULL CHECK (requested_quantity > 0)` | Quantidade ou contagem mensurável. |
| `unit_price` | `DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0)` | Valor monetário ou medida financeira. |
| `subtotal` | `DECIMAL(12,2) GENERATED ALWAYS AS (requested_quantity * unit_price) STORED` | Valor monetário ou medida financeira. |
| `order_date` | `TIMESTAMP NOT NULL` | Data de negócio e possível filtro temporal. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Exclusão lógica usada pelas consultas de pedido e recebimento. |

### `receiving`

**Por que existe:** Registra a conferência de mercadorias.

**Relacionamentos:** employee(employee_id), purchase_order(purchase_order_id, order_date).

| Campo | Definição SQL | Uso |
|---|---|---|
| `receiving_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `purchase_order_id` | `INTEGER NOT NULL` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `receiving_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `status` | `receiving_status NOT NULL DEFAULT 'PENDING'` | Estado atual do ciclo de vida. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `order_date` | `TIMESTAMP NOT NULL` | Data de negócio e possível filtro temporal. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `receiving_item`

**Por que existe:** Detalha itens e divergências recebidas.

**Relacionamentos:** purchase_order_item(purchase_order_item_id), receiving(receiving_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `receiving_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `receiving_id` | `INTEGER NOT NULL REFERENCES receiving(receiving_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `purchase_order_item_id` | `INTEGER NOT NULL REFERENCES purchase_order_item(purchase_order_item_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `received_quantity` | `DECIMAL(10,3) NOT NULL CHECK (received_quantity >= 0)` | Quantidade ou contagem mensurável. |
| `unit_price` | `DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0)` | Valor monetário ou medida financeira. |
| `manufacture_date` | `DATE` | Data de negócio e possível filtro temporal. |
| `expiration_date` | `DATE NOT NULL` | Data de negócio e possível filtro temporal. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `replenishment_execution`

**Por que existe:** Registra a execução da reposição.

**Relacionamentos:** employee(employee_id), replenishment_pre_list(pre_list_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `execution_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `pre_list_id` | `INTEGER NOT NULL REFERENCES replenishment_pre_list(pre_list_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `start_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `end_date` | `TIMESTAMP` | Data de negócio e possível filtro temporal. |
| `rating` | `INTEGER CHECK (rating BETWEEN 1 AND 5)` | Atributo do domínio desta entidade. |
| `comment` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `replenishment_execution_item`

**Por que existe:** Detalha o que foi efetivamente abastecido.

**Relacionamentos:** batch(batch_id), replenishment_execution(execution_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `execution_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `execution_id` | `INTEGER NOT NULL REFERENCES replenishment_execution(execution_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `batch_id` | `INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `replenished_quantity` | `DECIMAL(10,3) NOT NULL CHECK (replenished_quantity > 0)` | Quantidade ou contagem mensurável. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `replenishment_pre_list`

**Por que existe:** Registra a pré-lista sugerida de abastecimento.

**Relacionamentos:** employee(employee_id), retail_store(store_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `pre_list_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER REFERENCES employee(employee_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `generated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `status` | `pre_list_status NOT NULL DEFAULT 'GENERATED'` | Estado atual do ciclo de vida. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `replenishment_pre_list_item`

**Por que existe:** Detalha a sugestão por lote.

**Relacionamentos:** product(product_id), replenishment_pre_list(pre_list_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `pre_list_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `pre_list_id` | `INTEGER NOT NULL REFERENCES replenishment_pre_list(pre_list_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `suggested_quantity` | `DECIMAL(10,3) NOT NULL CHECK (suggested_quantity > 0)` | Quantidade ou contagem mensurável. |
| `priority` | `priority_level NOT NULL DEFAULT 'MEDIUM'` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `retail_store`

**Por que existe:** Representa uma loja da empresa.

**Relacionamentos:** address(address_id), company(company_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `store_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `company_id` | `INTEGER NOT NULL REFERENCES company(company_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `address_id` | `INTEGER NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(120) NOT NULL` | Atributo do domínio desta entidade. |
| `cnpj` | `CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj))` | Atributo do domínio desta entidade. |
| `email` | `VARCHAR(150) CHECK (fn_validate_email(email))` | Endereço eletrônico sujeito a validação e controle de acesso. |
| `phone` | `VARCHAR(20)` | Atributo do domínio desta entidade. |
| `latitude` | `DECIMAL(9,6) CHECK (latitude BETWEEN -90 AND 90)` | Atributo do domínio desta entidade. |
| `longitude` | `DECIMAL(9,6) CHECK (longitude BETWEEN -180 AND 180)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `sale_item`

**Por que existe:** Detalha produtos e lotes vendidos.

**Relacionamentos:** batch(batch_id), product(product_id), sales_transaction(sale_id, sale_date).

| Campo | Definição SQL | Uso |
|---|---|---|
| `sale_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `sale_id` | `INTEGER NOT NULL` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `batch_id` | `INTEGER REFERENCES batch(batch_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `quantity_sold` | `DECIMAL(10,3) NOT NULL CHECK (quantity_sold > 0)` | Quantidade ou contagem mensurável. |
| `unit_price` | `DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0)` | Valor monetário ou medida financeira. |
| `status` | `sale_item_status NOT NULL DEFAULT 'SOLD'` | Estado atual do ciclo de vida. |
| `canceled_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `subtotal` | `DECIMAL(12,2) GENERATED ALWAYS AS (quantity_sold * unit_price) STORED` | Valor monetário ou medida financeira. |
| `sale_date` | `TIMESTAMP NOT NULL` | Data de negócio e possível filtro temporal. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `sale_payment`

**Por que existe:** Registra os pagamentos da venda.

**Relacionamentos:** sales_transaction(sale_id, sale_date).

| Campo | Definição SQL | Uso |
|---|---|---|
| `sale_payment_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `sale_id` | `INTEGER NOT NULL` | Identificador ou chave de correlação. |
| `sale_date` | `TIMESTAMP NOT NULL` | Data de negócio e possível filtro temporal. |
| `payment_method` | `payment_method NOT NULL` | Atributo do domínio desta entidade. |
| `amount` | `DECIMAL(12,2) NOT NULL CHECK (amount > 0)` | Valor monetário ou medida financeira. |
| `installments` | `INTEGER NOT NULL DEFAULT 1 CHECK (installments > 0)` | Atributo do domínio desta entidade. |
| `authorization_code` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `nsu` | `VARCHAR(100)` | Atributo do domínio desta entidade. |
| `transaction_id` | `VARCHAR(150)` | Identificador ou chave de correlação. |
| `paid_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `sales_transaction`

**Por que existe:** Registra o cabeçalho da venda.

**Relacionamentos:** customer(customer_id), employee(employee_id), pos_shift(shift_id), retail_store(store_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `sale_id` | `INTEGER GENERATED ALWAYS AS IDENTITY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `shift_id` | `INTEGER NOT NULL REFERENCES pos_shift(shift_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `customer_id` | `INTEGER REFERENCES customer(customer_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `customer_document` | `VARCHAR(80)` | Token `DOC_SHA256_<64-hex>`; nunca contém CPF ou CNPJ aberto. |
| `sale_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `total_amount` | `DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0)` | Valor monetário ou medida financeira. |
| `status` | `sale_status NOT NULL DEFAULT 'COMPLETED'` | Estado atual do ciclo de vida. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |
| `version` | `INTEGER DEFAULT 1` | Versão para evolução ou concorrência otimista. |

### `sales_transaction_archive`

**Por que existe:** Arquiva vendas.

**Relacionamentos:** LIKE sales_transaction.

| Campo | Definição SQL | Uso |
|---|---|---|

### `schema_version`

**Por que existe:** Controla a versão instalada do schema.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `version_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `version` | `VARCHAR(20) NOT NULL UNIQUE` | Versão para evolução ou concorrência otimista. |
| `description` | `VARCHAR(200) NOT NULL` | Atributo do domínio desta entidade. |
| `type` | `migration_type NOT NULL DEFAULT 'SQL'` | Atributo do domínio desta entidade. |
| `script` | `VARCHAR(100) NOT NULL` | Atributo do domínio desta entidade. |
| `checksum` | `VARCHAR(64)` | Atributo do domínio desta entidade. |
| `installed_by` | `VARCHAR(100) NOT NULL` | Atributo do domínio desta entidade. |
| `installed_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `execution_time` | `INTEGER` | Atributo do domínio desta entidade. |
| `success` | `BOOLEAN NOT NULL DEFAULT TRUE` | Atributo do domínio desta entidade. |

### `store_product_price`

**Por que existe:** Versiona preço efetivo por loja.

**Relacionamentos:** product(product_id), retail_store(store_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `store_product_price_id` | `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `regular_price` | `DECIMAL(12,2) NOT NULL CHECK (regular_price > 0)` | Valor monetário ou medida financeira. |
| `valid_from` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Atributo do domínio desta entidade. |
| `valid_until` | `TIMESTAMPTZ` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `version` | `INTEGER NOT NULL DEFAULT 1 CHECK (version > 0)` | Versão para evolução ou concorrência otimista. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP` | Data e hora usada para auditoria ou processamento. |

### `subscription_plan`

**Por que existe:** Define planos e limites comerciais.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `plan_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `name` | `VARCHAR(100) NOT NULL UNIQUE` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `price` | `DECIMAL(10,2) NOT NULL CHECK (price >= 0)` | Valor monetário ou medida financeira. |
| `store_limit` | `INTEGER NOT NULL CHECK (store_limit > 0)` | Atributo do domínio desta entidade. |
| `user_limit` | `INTEGER NOT NULL CHECK (user_limit > 0)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `suggested_action`

**Por que existe:** Registra ação proposta e sua decisão.

**Relacionamentos:** alert(alert_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `suggested_action_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `alert_id` | `INTEGER NOT NULL REFERENCES alert(alert_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `action_type` | `suggested_action_type NOT NULL` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `priority` | `priority_level NOT NULL DEFAULT 'MEDIUM'` | Atributo do domínio desta entidade. |
| `status` | `suggested_action_status NOT NULL DEFAULT 'PENDING'` | Estado atual do ciclo de vida. |
| `generated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `source_recommendation_uuid` | `UUID UNIQUE` | Correlação idempotente com a recomendação analítica. |

### `supplier`

**Por que existe:** Cadastra fornecedores.

**Relacionamentos:** address(address_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `supplier_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `address_id` | `INTEGER NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `trade_name` | `VARCHAR(150) NOT NULL` | Atributo do domínio desta entidade. |
| `cnpj` | `CHAR(14) NOT NULL UNIQUE CHECK (fn_validate_cnpj(cnpj))` | Atributo do domínio desta entidade. |
| `email` | `VARCHAR(150) CHECK (fn_validate_email(email))` | Endereço eletrônico sujeito a validação e controle de acesso. |
| `phone` | `VARCHAR(20)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `supplier_history`

**Por que existe:** Preserva alterações do fornecedor.

**Relacionamentos:** app_user(user_id), supplier(supplier_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `history_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `supplier_id` | `INTEGER REFERENCES supplier(supplier_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `field_name` | `VARCHAR(50) NOT NULL` | Atributo do domínio desta entidade. |
| `old_value` | `TEXT` | Valor monetário ou medida financeira. |
| `new_value` | `TEXT` | Valor monetário ou medida financeira. |
| `changed_by` | `INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL` | Atributo do domínio desta entidade. |
| `changed_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Atributo do domínio desta entidade. |

### `supplier_product`

**Por que existe:** Relaciona catálogo, preço e prazo do fornecedor.

**Relacionamentos:** product(product_id), supplier(supplier_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `supplier_product_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `supplier_id` | `INTEGER NOT NULL REFERENCES supplier(supplier_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `product_id` | `INTEGER NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `supplier_code` | `VARCHAR(50)` | Atributo do domínio desta entidade. |
| `purchase_price` | `DECIMAL(10,2) NOT NULL CHECK (purchase_price >= 0)` | Valor monetário ou medida financeira. |
| `lead_time` | `INTEGER NOT NULL CHECK (lead_time >= 0)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `system_log`

**Por que existe:** Registra eventos técnicos.

**Relacionamentos:** app_user(user_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `log_id` | `BIGSERIAL PRIMARY KEY` | Identificador ou chave de correlação. |
| `log_level` | `log_level NOT NULL` | Atributo do domínio desta entidade. |
| `module` | `VARCHAR(50)` | Atributo do domínio desta entidade. |
| `message` | `TEXT NOT NULL` | Atributo do domínio desta entidade. |
| `stack_trace` | `TEXT` | Atributo do domínio desta entidade. |
| `user_id` | `INTEGER REFERENCES app_user(user_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `ip_address` | `INET` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `system_rule`

**Por que existe:** Mantém regras parametrizáveis.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `rule_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `rule_category` | `VARCHAR(30) NOT NULL` | Atributo do domínio desta entidade. |
| `rule_key` | `VARCHAR(60) NOT NULL` | Atributo do domínio desta entidade. |
| `rule_name` | `VARCHAR(120)` | Atributo do domínio desta entidade. |
| `rule_value` | `TEXT` | Valor monetário ou medida financeira. |
| `value_type` | `VARCHAR(20) NOT NULL DEFAULT 'TEXT'` | Valor monetário ou medida financeira. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |

### `tax_profile`

**Por que existe:** Centraliza regras tributárias do produto.

**Relacionamentos:** não possui FK declarada nesta tabela.

| Campo | Definição SQL | Uso |
|---|---|---|
| `tax_profile_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `code` | `VARCHAR(30) NOT NULL UNIQUE` | Atributo do domínio desta entidade. |
| `name` | `VARCHAR(120) NOT NULL` | Atributo do domínio desta entidade. |
| `description` | `TEXT` | Atributo do domínio desta entidade. |
| `cfop` | `VARCHAR(4)` | Atributo do domínio desta entidade. |
| `icms_cst` | `VARCHAR(3)` | Atributo do domínio desta entidade. |
| `icms_csosn` | `VARCHAR(4)` | Atributo do domínio desta entidade. |
| `icms_rate` | `DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (icms_rate BETWEEN 0 AND 100)` | Atributo do domínio desta entidade. |
| `ipi_cst` | `VARCHAR(2)` | Atributo do domínio desta entidade. |
| `ipi_rate` | `DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (ipi_rate BETWEEN 0 AND 100)` | Atributo do domínio desta entidade. |
| `pis_cst` | `VARCHAR(2)` | Atributo do domínio desta entidade. |
| `pis_rate` | `DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (pis_rate BETWEEN 0 AND 100)` | Atributo do domínio desta entidade. |
| `cofins_cst` | `VARCHAR(2)` | Atributo do domínio desta entidade. |
| `cofins_rate` | `DECIMAL(7,4) NOT NULL DEFAULT 0 CHECK (cofins_rate BETWEEN 0 AND 100)` | Atributo do domínio desta entidade. |
| `active` | `BOOLEAN NOT NULL DEFAULT TRUE` | Indica se o registro pode ser utilizado. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `deleted_at` | `TIMESTAMP` | Atributo do domínio desta entidade. |

### `transfer`

**Por que existe:** Controla transferência entre lojas.

**Relacionamentos:** employee(employee_id), retail_store(store_id), suggested_action(suggested_action_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `transfer_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `suggested_action_id` | `INTEGER REFERENCES suggested_action(suggested_action_id) ON DELETE SET NULL` | Identificador ou chave de correlação. |
| `source_store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `destination_store_id` | `INTEGER NOT NULL REFERENCES retail_store(store_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `employee_id` | `INTEGER NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `request_date` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data de negócio e possível filtro temporal. |
| `completion_date` | `TIMESTAMP` | Data de negócio e possível filtro temporal. |
| `status` | `transfer_status NOT NULL DEFAULT 'REQUESTED'` | Estado atual do ciclo de vida. |
| `observation` | `TEXT` | Atributo do domínio desta entidade. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `updated_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
| `version` | `INTEGER DEFAULT 1` | Versão para evolução ou concorrência otimista. |

### `transfer_item`

**Por que existe:** Detalha lotes transferidos.

**Relacionamentos:** batch(batch_id), transfer(transfer_id).

| Campo | Definição SQL | Uso |
|---|---|---|
| `transfer_item_id` | `INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY` | Identificador ou chave de correlação. |
| `transfer_id` | `INTEGER NOT NULL REFERENCES transfer(transfer_id) ON DELETE CASCADE` | Identificador ou chave de correlação. |
| `batch_id` | `INTEGER NOT NULL REFERENCES batch(batch_id) ON DELETE RESTRICT` | Identificador ou chave de correlação. |
| `transferred_quantity` | `DECIMAL(10,3) NOT NULL CHECK (transferred_quantity > 0)` | Quantidade ou contagem mensurável. |
| `created_at` | `TIMESTAMP NOT NULL DEFAULT NOW()` | Data e hora usada para auditoria ou processamento. |
