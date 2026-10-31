SET search_path TO mottainai, public;

-- Substitui a consulta herdada a pg_partitions (view que nao existe no
-- PostgreSQL) pelo catalogo nativo de heranca/particionamento.
CREATE OR REPLACE PROCEDURE sp_drop_old_partitions(p_months_to_keep INTEGER DEFAULT 12)
LANGUAGE plpgsql AS $$
DECLARE
    v_cutoff_date DATE := date_trunc('month', current_date)
        - make_interval(months => p_months_to_keep);
    v_partition RECORD;
BEGIN
    IF p_months_to_keep < 1 THEN
        RAISE EXCEPTION 'p_months_to_keep must be greater than zero';
    END IF;

    FOR v_partition IN
        SELECT child_ns.nspname AS schema_name, child.relname AS partition_name
        FROM pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
        JOIN pg_class child ON child.oid = inheritance.inhrelid
        JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
        WHERE parent_ns.nspname = 'mottainai'
          AND parent.relname IN (
              'inventory_movement', 'sales_transaction', 'audit_log', 'purchase_order'
          )
          AND child.relname ~ '_[0-9]{4}_[0-9]{2}$'
          AND to_date(substring(child.relname FROM '([0-9]{4}_[0-9]{2})$'), 'YYYY_MM')
              < v_cutoff_date
    LOOP
        EXECUTE format(
            'DROP TABLE IF EXISTS %I.%I',
            v_partition.schema_name,
            v_partition.partition_name
        );
    END LOOP;
END;
$$;
