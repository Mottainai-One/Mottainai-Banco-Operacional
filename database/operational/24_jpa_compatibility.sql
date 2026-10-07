-- Atualização aditiva para um banco mottainai_operational já instalado.
-- Usar update_existing_jpa.sql para aplicar em banco existente; o install.sql
-- inclui este arquivo na instalação limpa. Ambos abrem uma transação.
-- Pode ser repetida; não apaga usuários nem tokens.
-- Alvo: esquema mottainai e entidade AppUser/PasswordResetToken do HEAD
-- 7d4d521 de Mottainai-Spring-Api-SQL em 2026-10-06.
-- IMPORTANTE: este script alinha COLUNAS. Não substitui as migrações Flyway
-- da API nem resolve sozinho a tokenização irreversível de e-mails da versão
-- 22_sensitive_data_contract.sql; veja as notas ao final.

SET LOCAL search_path TO mottainai, public;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
    IF to_regclass('mottainai.app_user') IS NULL THEN
        RAISE EXCEPTION 'Tabela mottainai.app_user não existe. Instale o banco operacional primeiro.';
    END IF;
END $$;

-- Estado do convite inicial. TRUE preserva o estado das contas já existentes.
ALTER TABLE mottainai.app_user
    ADD COLUMN IF NOT EXISTS password_set BOOLEAN NOT NULL DEFAULT TRUE;

-- Necessário para AppUser.tokenVersion e invalidação dos JWTs antigos.
ALTER TABLE mottainai.app_user
    ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;

-- Necessário para AppUser.firebaseUid. NULL para contas sem vínculo Firebase.
ALTER TABLE mottainai.app_user
    ADD COLUMN IF NOT EXISTS firebase_uid VARCHAR(255);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.app_user'::regclass
          AND conname = 'ck_app_user_token_version_nonnegative'
    ) THEN
        ALTER TABLE mottainai.app_user
            ADD CONSTRAINT ck_app_user_token_version_nonnegative
            CHECK (token_version >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.app_user'::regclass
          AND conname = 'uq_app_user_firebase_uid'
    ) THEN
        ALTER TABLE mottainai.app_user
            ADD CONSTRAINT uq_app_user_firebase_uid UNIQUE (firebase_uid);
    END IF;
END $$;

COMMENT ON COLUMN mottainai.app_user.password_set IS
    'TRUE após o funcionário definir a senha inicial; convite novo usa FALSE.';
COMMENT ON COLUMN mottainai.app_user.token_version IS
    'Versão do token JWT; incrementar quando a senha ou autorização mudar.';

-- A versão operacional endurecida usa recovery_token_id/token_hash, enquanto
-- o JPA atual espera password_reset_token_id/code_hash/attempts. Mantemos os
-- nomes antigos usados pelas funções do banco e acrescentamos aliases reais.
-- Bancos locais instalados antes de 04_additional_tables.sql não têm esta
-- tabela. Criá-la aqui evita exigir reinstalação e preserva instalações novas.
CREATE TABLE IF NOT EXISTS mottainai.password_reset_token (
    recovery_token_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES mottainai.app_user(user_id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    requested_ip INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    token_type VARCHAR(30) NOT NULL DEFAULT 'PASSWORD_RESET'
        CHECK (token_type IN ('PASSWORD_RESET', 'EMPLOYEE_INVITATION')),
    CHECK (expires_at > created_at),
    CHECK (used_at IS NULL OR used_at >= created_at)
);

ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS password_reset_token_id INTEGER;
ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS code_hash VARCHAR(255);
ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS token_hash TEXT;
ALTER TABLE mottainai.password_reset_token
    ADD COLUMN IF NOT EXISTS token_type VARCHAR(30) NOT NULL DEFAULT 'PASSWORD_RESET';

CREATE SEQUENCE IF NOT EXISTS mottainai.password_reset_token_jpa_id_seq AS INTEGER;
DO $$
DECLARE
    v_is_identity TEXT;
BEGIN
    SELECT is_identity INTO v_is_identity
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'password_reset_token'
      AND column_name = 'password_reset_token_id';
    IF v_is_identity <> 'YES' THEN
        ALTER SEQUENCE mottainai.password_reset_token_jpa_id_seq
            OWNED BY mottainai.password_reset_token.password_reset_token_id;
        ALTER TABLE mottainai.password_reset_token
            ALTER COLUMN password_reset_token_id
            SET DEFAULT nextval('mottainai.password_reset_token_jpa_id_seq'::regclass);
    END IF;
END $$;

-- Reserva a sequência acima dos IDs eventualmente já existentes.
DO $$
DECLARE
    v_is_identity TEXT;
BEGIN
    SELECT is_identity INTO v_is_identity
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'password_reset_token'
      AND column_name = 'password_reset_token_id';
    IF v_is_identity <> 'YES' THEN
        PERFORM setval(
            'mottainai.password_reset_token_jpa_id_seq'::regclass,
            GREATEST(COALESCE((SELECT MAX(password_reset_token_id)
                               FROM mottainai.password_reset_token), 0), 1),
            EXISTS (SELECT 1 FROM mottainai.password_reset_token
                    WHERE password_reset_token_id IS NOT NULL)
        );
    END IF;
END $$;

DO $$
DECLARE
    v_is_identity TEXT;
BEGIN
    SELECT is_identity INTO v_is_identity
    FROM information_schema.columns
    WHERE table_schema = 'mottainai'
      AND table_name = 'password_reset_token'
      AND column_name = 'password_reset_token_id';
    IF v_is_identity <> 'YES' THEN
        UPDATE mottainai.password_reset_token
        SET password_reset_token_id =
            nextval('mottainai.password_reset_token_jpa_id_seq'::regclass)
        WHERE password_reset_token_id IS NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'password_reset_token'
          AND column_name = 'token_hash'
    ) THEN
        EXECUTE 'UPDATE mottainai.password_reset_token
                 SET code_hash = token_hash
                 WHERE code_hash IS NULL';
    END IF;
END $$;

UPDATE mottainai.password_reset_token
SET token_hash = code_hash
WHERE token_hash IS NULL AND code_hash IS NOT NULL;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM mottainai.password_reset_token
               WHERE code_hash IS NULL OR token_hash IS NULL
                  OR password_reset_token_id IS NULL) THEN
        RAISE EXCEPTION 'Não foi possível preencher os aliases de hash/ID do token.';
    END IF;
END $$;

ALTER TABLE mottainai.password_reset_token
    ALTER COLUMN password_reset_token_id SET NOT NULL;
ALTER TABLE mottainai.password_reset_token
    ALTER COLUMN code_hash SET NOT NULL;
ALTER TABLE mottainai.password_reset_token
    ALTER COLUMN token_hash SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_password_reset_token_token_hash_compat
    ON mottainai.password_reset_token (token_hash);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.password_reset_token'::regclass
          AND conname = 'uq_password_reset_token_jpa_id'
    ) THEN
        ALTER TABLE mottainai.password_reset_token
            ADD CONSTRAINT uq_password_reset_token_jpa_id
            UNIQUE (password_reset_token_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mottainai.password_reset_token'::regclass
          AND conname = 'ck_password_reset_attempts_nonnegative'
    ) THEN
        ALTER TABLE mottainai.password_reset_token
            ADD CONSTRAINT ck_password_reset_attempts_nonnegative
            CHECK (attempts >= 0);
    END IF;
END $$;

-- Nas instalações endurecidas, token_hash é NOT NULL e alimenta funções do
-- banco. O JPA escreve code_hash. Este trigger sincroniza os dois sentidos.
CREATE OR REPLACE FUNCTION mottainai.fn_sync_password_reset_hash_alias()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = mottainai, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.code_hash IS NULL THEN NEW.code_hash := NEW.token_hash; END IF;
        IF NEW.token_hash IS NULL THEN NEW.token_hash := NEW.code_hash; END IF;
    ELSE
        IF NEW.code_hash IS DISTINCT FROM OLD.code_hash THEN
            NEW.token_hash := NEW.code_hash;
        ELSIF NEW.token_hash IS DISTINCT FROM OLD.token_hash THEN
            NEW.code_hash := NEW.token_hash;
        END IF;
    END IF;
    IF NEW.code_hash IS DISTINCT FROM NEW.token_hash THEN
        RAISE EXCEPTION 'code_hash e token_hash divergentes';
    END IF;
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'mottainai'
          AND table_name = 'password_reset_token'
          AND column_name = 'token_hash'
    ) THEN
        DROP TRIGGER IF EXISTS trg_sync_password_reset_hash_alias
            ON mottainai.password_reset_token;
        CREATE TRIGGER trg_sync_password_reset_hash_alias
            BEFORE INSERT OR UPDATE OF code_hash, token_hash
            ON mottainai.password_reset_token
            FOR EACH ROW EXECUTE FUNCTION mottainai.fn_sync_password_reset_hash_alias();
    END IF;
END $$;

-- O JPA gera o identificador e faz INSERT; a role precisa usar a sequência.
DO $$
DECLARE
    v_recovery_sequence TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mottainai_api') THEN
        GRANT USAGE, SELECT ON SEQUENCE
            mottainai.password_reset_token_jpa_id_seq TO mottainai_api;

        -- Se a tabela foi criada apenas nesta atualização em uma instalação
        -- já endurecida, restaurar a mesma política de 20_security_hardening.
        IF to_regprocedure('mottainai.fn_can_access_user(integer)') IS NOT NULL THEN
            ALTER TABLE mottainai.password_reset_token ENABLE ROW LEVEL SECURITY;
            IF NOT EXISTS (
                SELECT 1 FROM pg_policies
                WHERE schemaname = 'mottainai'
                  AND tablename = 'password_reset_token'
                  AND policyname = 'password_reset_token_policy'
            ) THEN
                CREATE POLICY password_reset_token_policy
                    ON mottainai.password_reset_token FOR ALL TO mottainai_api
                    USING (mottainai.fn_can_access_user(user_id))
                    WITH CHECK (mottainai.fn_can_access_user(user_id));
            END IF;
            GRANT SELECT, INSERT, UPDATE ON mottainai.password_reset_token
                TO mottainai_api;
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'mottainai'
                  AND table_name = 'password_reset_token'
                  AND column_name = 'recovery_token_id'
            ) THEN
                v_recovery_sequence := pg_get_serial_sequence(
                    'mottainai.password_reset_token', 'recovery_token_id');
                IF v_recovery_sequence IS NOT NULL THEN
                    EXECUTE format(
                        'GRANT USAGE, SELECT ON SEQUENCE %s TO mottainai_api',
                        v_recovery_sequence);
                END IF;
            END IF;
        END IF;
    END IF;
END $$;

-- Validação estrutural da migração, sem expor valores pessoais.
DO $$
DECLARE
    v_missing TEXT;
BEGIN
    SELECT string_agg(required.name, ', ')
    INTO v_missing
    FROM (VALUES ('password_set'), ('token_version'), ('firebase_uid')) AS required(name)
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns c
        WHERE c.table_schema = 'mottainai'
          AND c.table_name = 'app_user'
          AND c.column_name = required.name
    );
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Campos app_user ausentes: %', v_missing;
    END IF;
END $$;


-- VERIFICAÇÃO MANUAL APÓS EXECUTAR:
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema='mottainai' AND table_name='app_user'
-- ORDER BY ordinal_position;
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema='mottainai' AND table_name='password_reset_token'
-- ORDER BY ordinal_position;

-- LIMITES IMPORTANTES:
-- 1) A API Flyway V9 cria password_reset_token sem IF NOT EXISTS. Se o Flyway
--    não estiver sincronizado com esse banco, a inicialização ainda falhará;
--    não altere flyway_schema_history manualmente sem plano de baseline.
-- 2) Se 22_sensitive_data_contract.sql foi executado, e-mails foram convertidos
--    em tokens SHA-256. O JPA atual pesquisa e envia e-mail em texto puro;
--    SQL não consegue recuperar o e-mail original. A API precisa adaptar o
--    lookup e manter canal seguro de entrega; esta migração não corrige isso.
-- 3) O JPA atual apaga tokens antigos via deleteByUserId. A role endurecida
--    não recebe DELETE na tabela. Não ampliamos o privilégio aqui: o serviço
--    deve passar a marcar tokens usados/revogados e manter auditoria.
-- 4) password_set foi criado no banco, mas AppUser.java ainda não o mapeia.
--    O campo existirá; a API só controlará o fluxo de convite após mapear
--    esse atributo e definir FALSE/TRUE nos momentos corretos.
