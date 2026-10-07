# Mottainai-Banco-Operacional

Core operational PostgreSQL database of the Mottainai ecosystem, designed to support predictive inventory management, batch traceability, replenishment processes, business operations, and seamless integration with all software modules.

## Installation

Run the versioned installer with PostgreSQL 15 or newer:

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_operational \
  -f database/operational/install.sql
```

The final modules establish least-privilege security, the sensitive-data
contract and JPA compatibility:

- `20_security_hardening.sql`: tenant isolation, sessions, privileges and audit;
- `22_sensitive_data_contract.sql`: SHA-256 tokens, BCrypt constraints, customer
  isolation, consent history, log redaction and RPA correlation;
- `24_jpa_compatibility.sql`: additive `app_user` fields and password-reset
  compatibility, including creation of `password_reset_token` when absent.

For a **database already installed locally**, run the incremental update instead
of reinstalling the entire schema:

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_operational \
  -f database/operational/update_existing_jpa.sql
```

`update_existing_jpa.sql` runs module 24 in one transaction. It is
repeatable and does not delete existing users or reset tokens. Use a database
owner or migration role with permission to alter tables and create sequences.
It fixes the missing `mottainai.password_reset_token` case reported on an older
local installation. Verify application Flyway history separately; an existing
database cannot safely be relabeled as having applied the API's migrations.

The installer also supports managed PostgreSQL administrators that have
`CREATEROLE` but are not `SUPERUSER`. Privileged role attributes are verified
instead of being altered by an account that cannot legally change them.

The database does not accept raw CPF, customer documents, customer identity
values or clear client contact data after module 22. Source backends must apply
the documented treatment before persistence. See
`docs/DOCUMENTACAO_BANCO_OPERACIONAL_2026-09-20.md` for the complete contract.
