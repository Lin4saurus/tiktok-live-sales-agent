#!/bin/bash
# Se ejecuta solo la primera vez que se crea el volumen de Postgres.
# Después hay que aplicar el esquema de ventas: powershell -File db\aplicar_migraciones.ps1
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    CREATE DATABASE n8n;
    CREATE DATABASE evolution;
    CREATE DATABASE ventas;
EOSQL
