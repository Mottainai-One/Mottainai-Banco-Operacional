# Banco Operacional Mottainai

Este repositório contém scripts SQL para estruturar o banco PostgreSQL operacional do ecossistema Mottainai. Os scripts definem schemas, tipos, funções, tabelas, restrições, índices, gatilhos, views, dados de demonstração e rotinas de teste.

## Tecnologias

- PostgreSQL 15 ou superior, conforme os comentários e a CI do repositório.
- Cliente psql para executar os scripts.

## Organização dos scripts

O instalador script/install.sql encadeia os arquivos numerados de 00 a 10. O arquivo script/dataLoad.sql carrega dados de demonstração e é executado separadamente no workflow de CI.

## Instalação e segurança dos dados

Revise os scripts antes de executá-los e use uma instância descartável ou um banco preparado para essa versão. O script script/00_DataBase.sql executa DROP SCHEMA IF EXISTS mottainai CASCADE; isso remove o schema mottainai existente e seus objetos. Não rode o instalador sobre dados que devam ser preservados.

Com o PostgreSQL preparado, o mesmo fluxo usado pela CI é:

    cd script
    psql -h localhost -p 5432 -U mottainai -d mottainai -v ON_ERROR_STOP=1 -f install.sql

O usuário, host e banco acima correspondem ao serviço temporário de PostgreSQL definido no workflow. Ajuste-os apenas para uma instância local descartável. Depois, a carga de demonstração pode ser executada separadamente:

    psql -h localhost -p 5432 -U mottainai -d mottainai -v ON_ERROR_STOP=1 -f dataLoad.sql

O workflow Database CI valida a instalação em PostgreSQL 15, executa a carga duas vezes para verificar idempotência e aplica verificações básicas de estilo SQL. As funções da suíte de banco são instaladas por install.sql, mas não são chamadas automaticamente por ele.

O [Hub](https://github.com/Mottainai-One/Mottainai-Hub/tree/main/Docs/banco) mantém a documentação de arquitetura e operação do ecossistema. Compare o contrato documentado com os scripts desta branch antes de usá-los como fonte de uma instalação existente; o instalador descrito acima remove o schema operacional antes de recriá-lo.

## Escopo e licença

Este README descreve o conteúdo versionado neste repositório. Confira os scripts e o contrato do banco antes de integrar uma aplicação. A licença está em [LICENSE](LICENSE).
