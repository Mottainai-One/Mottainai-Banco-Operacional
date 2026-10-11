# Mottainai-Banco-Operacional

Core operational PostgreSQL database of the Mottainai ecosystem, designed to support predictive inventory management, batch traceability, replenishment processes, business operations, and seamless integration with all software modules.

## Installation

Run the versioned installer with PostgreSQL 15 or newer:

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_operational \
  -f database/operational/install.sql
```

The final modules establish company ownership, least-privilege security, the
sensitive-data contract and API/RPA compatibility:

- `10_product_company.sql`: company ownership, tenant-scoped SKU/barcode and
  product RLS;
- `20_security_hardening.sql`: tenant isolation, sessions, privileges and audit;
- `22_sensitive_data_contract.sql`: SHA-256 tokens, BCrypt constraints, customer
  isolation, consent history, log redaction and RPA correlation;
- `24_jpa_compatibility.sql`: additive `app_user` fields and password-reset
  compatibility, including creation of `password_reset_token` when absent;
- `25_api_rpa_compatibility.sql`: API views/functions, missing soft-delete
  columns, enum values, tenant monitoring and controlled legacy-import context.

For a **database already installed locally**, run the incremental update instead
of reinstalling the entire schema:

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_operational \
  -f database/operational/update_existing_api_rpa.sql
```

`update_existing_api_rpa.sql` runs modules 10, 20, 22, 24 and 25 in one
transaction. It is repeatable and does not delete existing users or reset
tokens. The product migration stops if ownership is ambiguous instead of
guessing a company. Use a database owner or migration role with permission to
alter tables, create sequences and manage the three group roles. Verify
application Flyway history separately; an existing database cannot safely be
relabeled as having applied the API's migrations.

The installer also supports managed PostgreSQL administrators that have
`CREATEROLE` but are not `SUPERUSER`. Privileged role attributes are verified
instead of being altered by an account that cannot legally change them.

The database does not accept raw CPF, customer documents, customer identity
values or clear client contact data after module 22. Source backends must apply
the documented treatment before persistence. See
`docs/DOCUMENTACAO_BANCO_OPERACIONAL_2026-09-20.md` for the complete contract.
