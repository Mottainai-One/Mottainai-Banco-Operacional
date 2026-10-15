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
