\set ON_ERROR_STOP on

CREATE ROLE mottainai_qa_analytics_read LOGIN INHERIT NOCREATEDB NOCREATEROLE
    NOSUPERUSER NOBYPASSRLS PASSWORD :'qa_reader_password';
GRANT mottainai_analytics_reader TO mottainai_qa_analytics_read;
GRANT CONNECT ON DATABASE mottainai_qa_analytics TO mottainai_qa_analytics_read;
