# Mottainai-Banco-Operacional

Core operational PostgreSQL database of the Mottainai ecosystem, designed to support predictive inventory management, batch traceability, replenishment processes, business operations, and seamless integration with all software modules.

## Installation

Run the versioned installer with PostgreSQL 15 or newer:

```bash
psql -v ON_ERROR_STOP=1 -d mottainai_operational \
  -f database/operational/install.sql
```

The final modules establish professional least-privilege security and the
sensitive-data contract:

- `20_security_hardening.sql`: tenant isolation, sessions, privileges and audit;
- `21_security_hardening_tests.sql`: structural security assertions;
- `22_sensitive_data_contract.sql`: SHA-256 tokens, BCrypt constraints, customer
  isolation, consent history, log redaction and RPA correlation;
- `23_sensitive_data_contract_tests.sql`: protected-data assertions.

The database does not accept raw CPF, customer documents, customer identity
values or clear client contact data after module 22. Source backends must apply
the documented treatment before persistence. See
`docs/DOCUMENTACAO_BANCO_OPERACIONAL_2026-09-20.md` for the complete contract.
