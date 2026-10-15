\set ON_ERROR_STOP on

-- The API connects with this login, inheriting only the existing API group role.
CREATE ROLE mottainai_qa_app LOGIN INHERIT NOCREATEDB NOCREATEROLE
    PASSWORD :'qa_app_password';
GRANT mottainai_api TO mottainai_qa_app;
