SET search_path TO mottainai_analytics, public;

INSERT INTO dim_date (
    date_key, year_number, quarter_number, month_number, month_name,
    week_number, day_number, day_of_week_number, day_of_week_name, is_weekend
)
SELECT
    day::date,
    extract(year FROM day)::smallint,
    extract(quarter FROM day)::smallint,
    extract(month FROM day)::smallint,
    to_char(day, 'TMMonth'),
    extract(week FROM day)::smallint,
    extract(day FROM day)::smallint,
    extract(isodow FROM day)::smallint,
    to_char(day, 'TMDay'),
    extract(isodow FROM day) IN (6, 7)
FROM generate_series(
    date_trunc('year', current_date) - interval '5 years',
    date_trunc('year', current_date) + interval '3 years' - interval '1 day',
    interval '1 day'
) AS calendar(day)
ON CONFLICT (date_key) DO NOTHING;

INSERT INTO ai_model (name, model_type, version, parameters)
VALUES
    ('Previsao de Demanda', 'DEMAND_FORECAST', '1.0.0', '{"horizon_days": 30}'),
    ('Risco de Validade', 'EXPIRY_RISK', '1.0.0', '{"warning_days": [30, 15, 7]}'),
    ('Otimizacao de Preco', 'PRICE_OPTIMIZATION', '1.0.0', '{"min_margin_percent": 5}')
ON CONFLICT (name, version) DO NOTHING;

INSERT INTO schema_version (version, description)
VALUES (10, 'Separacao fisica do banco analitico e de IA')
ON CONFLICT (version) DO NOTHING;
