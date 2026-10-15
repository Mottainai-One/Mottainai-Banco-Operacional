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

O QA completo ainda requer a API Spring, a IA, os testes de integração e um servidor acessível à equipe.

## Etapa 2: API Spring com o banco de QA

Clone `Mottainai-Spring-Api-SQL` ao lado deste repositório. Enquanto a PR da imagem da API não for integrada, use a branch `feature/qa-api-container`; depois use `main`. Acrescente `QA_JWT_SECRET` ao `qa/.env` com um segredo Base64 gerado a partir de pelo menos 32 bytes aleatórios. Não publique esse arquivo.

Na raiz deste repositório, suba e valide os serviços:

```bash
docker compose --env-file qa/.env -f qa/compose.yaml -f qa/compose.api.yaml -f qa/compose.local.yaml -f qa/compose.api.local.yaml up -d --build api
docker compose --env-file qa/.env -f qa/compose.yaml -f qa/compose.api.yaml --profile verify run --rm verify-api
```

No uso local, a API fica em `http://localhost:18080`. Verifique `http://localhost:18080/actuator/health` e `http://localhost:18080/swagger-ui.html`. Para o servidor compartilhado, omita os dois arquivos `*.local.yaml`: nem PostgreSQL nem API terão uma porta publicada diretamente. A futura configuração HTTPS será a única entrada pública.

Esta etapa verifica que a API inicia contra o esquema operacional de QA e serve health/OpenAPI. Ela não substitui os testes unitários da API nem os cenários completos de negócio, que devem permanecer visíveis na CI. O serviço de IA e a URL compartilhada virão em etapas seguintes.
