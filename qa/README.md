# Banco operacional de QA

Este é o primeiro componente do ambiente de QA compartilhado. Ele cria um PostgreSQL 15 isolado, instala o esquema oficial de `database/operational/install.sql` e cria um login de aplicação sem `SUPERUSER` nem `BYPASSRLS`. Não se conecta ao Aiven e não carrega dados reais.

## Uso local

1. Copie `qa/.env.example` para `qa/.env` e troque **ambas** as senhas por valores diferentes e aleatórios. Não versione `qa/.env`.
2. Na raiz deste repositório, execute `docker compose --env-file qa/.env -f qa/compose.yaml -f qa/compose.local.yaml up -d postgres`.
3. Valide com `docker compose --env-file qa/.env -f qa/compose.yaml --profile verify run --rm verify`.

A porta local opcional é `127.0.0.1:55432`. No servidor compartilhado, use somente `qa/compose.yaml`: a porta PostgreSQL não será publicada. A API e os demais serviços entrarão na rede interna em uma próxima etapa. O banco usa o volume `postgres_data`, portanto reiniciar o contêiner não apaga os dados.

O instalador do PostgreSQL só executa os scripts em `/docker-entrypoint-initdb.d` quando o volume está vazio. Atualizações futuras do esquema devem usar scripts de migração versionados; reiniciar o contêiner não reaplica `install.sql`. Para testar uma instalação limpa em um ambiente descartável, remova o volume desse ambiente de forma consciente e execute o `up` novamente.

## Critérios de aceite desta etapa

- PostgreSQL inicializa a partir de um volume vazio com `install.sql` oficial.
- O comando `verify` termina com código zero usando o login de aplicação.
- O login da aplicação não é superusuário nem tem `BYPASSRLS`.
- O Compose compartilhado não publica a porta do banco.
- Nenhuma senha real ou dado operacional é versionado.

O acesso compartilhado à equipe ainda requer um servidor e HTTPS.

## Etapa 2: API Spring com o banco de QA

Clone `Mottainai-Spring-Api-SQL` ao lado deste repositório e use a branch `main`, que já contém a imagem da API e o contrato atual do banco. Preencha `QA_JWT_SECRET`, `QA_STAFF_DATA_ENCRYPTION_KEY`, `QA_STAFF_DATA_LOOKUP_KEY` e `QA_CUSTOMER_DATA_ENCRYPTION_KEY` em `qa/.env`. As três chaves de dados devem ser valores Base64 distintos, cada um gerado a partir de exatamente 32 bytes aleatórios. Não publique esse arquivo.

Na raiz deste repositório, suba e valide os serviços:

```bash
docker compose --env-file qa/.env -f qa/compose.yaml -f qa/compose.api.yaml -f qa/compose.local.yaml -f qa/compose.api.local.yaml up -d --build api
docker compose --env-file qa/.env -f qa/compose.yaml -f qa/compose.api.yaml --profile verify run --rm verify-api
```

No uso local, a API fica em `http://localhost:18080`. Verifique `http://localhost:18080/actuator/health` e `http://localhost:18080/swagger-ui.html`. Os e-mails de teste ficam no Mailpit em `http://localhost:18025`; o SMTP de QA é interno à rede Docker e não envia mensagens para destinatários reais. Para o servidor compartilhado, omita os dois arquivos `*.local.yaml`: PostgreSQL, API e Mailpit não terão portas publicadas diretamente. A futura configuração HTTPS será a única entrada pública.

Esta etapa verifica que a API inicia contra o esquema operacional de QA e serve health/OpenAPI. Ela não substitui os testes unitários da API nem os cenários completos de negócio, que devem permanecer visíveis na CI. O serviço de IA e a URL compartilhada virão em etapas seguintes.

## IA e serviços de apoio

Clone `Mottainai-IA` ao lado deste repositório. Enquanto a PR de QA da IA estiver aberta, use `feature/qa-ia-stack`. Acrescente as variáveis `QA_IA_POSTGRES_DSN`, `QA_ANALYTICS_ADMIN_PASSWORD`, `QA_ANALYTICS_READER_PASSWORD`, `QA_IA_JWT_SECRET`, `QA_REDIS_PASSWORD`, `QA_MONGO_USER` e `QA_MONGO_PASSWORD` ao `qa/.env`; veja `qa/.env.example`. A senha PostgreSQL operacional na DSN deve ser codificada para URL se contiver caracteres reservados; para o leitor analítico use uma senha alfanumérica, pois o Compose monta a DSN. Use senhas próprias de QA, distintas das reais.

```bash
docker compose --env-file qa/.env -f qa/compose.yaml -f qa/compose.ia.yaml -f qa/compose.local.yaml -f qa/compose.ia.local.yaml up -d --build ia
docker compose --env-file qa/.env -f qa/compose.yaml -f qa/compose.ia.yaml --profile verify run --rm verify-ia
```

Localmente a IA responde em `http://localhost:18000/readyz`. O Compose instala um segundo PostgreSQL físico para o analítico, com usuário de leitura separado. MongoDB, Redis e os dois PostgreSQLs não publicam portas na configuração compartilhada. O teste de readiness exige os dois bancos, MongoDB e Redis; `/chat` só poderá ser validado quando houver uma chave de LLM exclusiva de QA e dados sintéticos adequados. A CI usa credenciais descartáveis e não configura provedor de LLM.

## Frontend e mobile

O frontend pode ser compilado e aberto como prévia local, acrescentando `qa/compose.frontend.yaml` e `qa/compose.frontend.local.yaml` ao comando Compose e usando `--profile preview`. Ele responde em `http://localhost:18081`. O login do frontend ainda é simulado por código com uma conta fixa: não publique essa prévia na Internet nem trate o fluxo como teste integrado de autenticação.

O aplicativo Android não é um serviço Docker. Emuladores no mesmo computador usam `apiBaseUrl=http://10.0.2.2:18080/` e `iaBaseUrl=http://10.0.2.2:18000/` no `local.properties` ignorado pelo Git. Veja `docs/QA-ENVIRONMENT.md` no repositório mobile. Antes de distribuir o APK à equipe, configure um projeto Firebase exclusivo de QA.

## RPA

O repositório RPA tem uma imagem de verificação que executa `pytest` sem rede e sem credenciais. O agendamento real e a carga operacional → analítico não são ativados pelo Compose de QA. Testes de ponta a ponta dessas cargas dependerão de bancos descartáveis e massa sintética.

## Estado da publicação compartilhada

Estes arquivos permitem executar e verificar os componentes em uma máquina Docker local ou em um runner de CI. A equipe ainda precisa de um servidor acessível, HTTPS e endpoints de QA para mobile antes que o ambiente seja disponibilizado a todos. Mantenha os bancos e serviços internos sem portas públicas quando fizer essa implantação.

### Contrato API e banco pendente

A migração `database/operational/29_finalize_reversible_employee_pii.sql` remove `app_user.cpf` e `app_user.email`. A entidade `AppUser` na branch atual da API ainda mapeia essas colunas. O job `10. API Spring conectada ao PostgreSQL de QA` da CI aponta essa incompatibilidade; a API precisa atualizar seu mapeamento e suas operações de identidade antes que a stack integrada seja aprovada. Não desative `ddl-auto=validate` para ignorar o problema. O teste da IA com os dois bancos físicos, MongoDB e Redis já passa separadamente.
