#!/bin/bash
set -e

# Use the variables injected by Docker via .env.db
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE TABLE IF NOT EXISTS "baubau_table" (
        id SERIAL PRIMARY KEY,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        is_mocochan BOOLEAN
    );

    -- Create the restricted user dynamically
    CREATE USER $APP_USER WITH PASSWORD '$APP_PASSWORD';
    
    -- Grant the minimal necessary privileges
    GRANT CONNECT ON DATABASE $POSTGRES_DB TO $APP_USER;
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "baubau_table" TO $APP_USER;
    GRANT USAGE, SELECT ON SEQUENCE baubau_table_id_seq TO $APP_USER;
EOSQL