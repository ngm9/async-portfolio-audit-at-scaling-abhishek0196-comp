-- In-place migration for an ALREADY-POPULATED tradingdb (the persisted pgdata
-- volume means init_database.sql will NOT re-run). Idempotent: safe to run more
-- than once. Run with autocommit (no surrounding BEGIN/COMMIT) so the
-- CREATE INDEX CONCURRENTLY statements are valid:
--
--   docker exec -i trading-postgres psql -U traderadmin -d tradingdb < migrate.sql
--
-- The CONCURRENTLY index builds avoid taking write locks on the large tables.
-- The NUMERIC type changes rewrite the table and DO take a brief ACCESS
-- EXCLUSIVE lock; run during a maintenance window if the tables are huge.

-- 1. Money/quantity columns: FLOAT8 -> exact NUMERIC. ----------------------
ALTER TABLE trades
    ALTER COLUMN amount TYPE NUMERIC(20, 4) USING amount::numeric(20, 4),
    ALTER COLUMN price  TYPE NUMERIC(20, 4) USING price::numeric(20, 4);

ALTER TABLE market_data
    ALTER COLUMN price  TYPE NUMERIC(20, 4) USING price::numeric(20, 4),
    ALTER COLUMN volume TYPE NUMERIC(20, 4) USING volume::numeric(20, 4);

-- 2. Referential integrity: make FK columns NOT NULL. ----------------------
--    Fails loudly if orphan/NULL rows exist; clean those first if so.
ALTER TABLE trades      ALTER COLUMN portfolio_id SET NOT NULL;
ALTER TABLE trades      ALTER COLUMN side         SET NOT NULL;
ALTER TABLE trades      ALTER COLUMN amount       SET NOT NULL;
ALTER TABLE trades      ALTER COLUMN price        SET NOT NULL;
ALTER TABLE audit_logs  ALTER COLUMN trade_id     SET NOT NULL;
ALTER TABLE market_data ALTER COLUMN price        SET NOT NULL;
ALTER TABLE market_data ALTER COLUMN volume       SET NOT NULL;

-- 3. Recreate FKs with ON DELETE RESTRICT (drop old unnamed/old FK first). --
DO $$
DECLARE c text;
BEGIN
    SELECT conname INTO c FROM pg_constraint
      WHERE conrelid = 'trades'::regclass AND contype = 'f'
        AND confrelid = 'portfolios'::regclass LIMIT 1;
    IF c IS NOT NULL THEN EXECUTE format('ALTER TABLE trades DROP CONSTRAINT %I', c); END IF;
    ALTER TABLE trades ADD CONSTRAINT fk_trades_portfolio
        FOREIGN KEY (portfolio_id) REFERENCES portfolios (id) ON DELETE RESTRICT;

    SELECT conname INTO c FROM pg_constraint
      WHERE conrelid = 'audit_logs'::regclass AND contype = 'f'
        AND confrelid = 'trades'::regclass LIMIT 1;
    IF c IS NOT NULL THEN EXECUTE format('ALTER TABLE audit_logs DROP CONSTRAINT %I', c); END IF;
    ALTER TABLE audit_logs ADD CONSTRAINT fk_audit_logs_trade
        FOREIGN KEY (trade_id) REFERENCES trades (id) ON DELETE RESTRICT;
END$$;

-- 4. UNIQUE(owner, name) on portfolios (no-op if it already exists). --------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_portfolios_owner_name'
    ) THEN
        ALTER TABLE portfolios
            ADD CONSTRAINT uq_portfolios_owner_name UNIQUE (owner, name);
    END IF;
END$$;

-- 5. Indexes on every hot filter/sort/FK column (lock-free builds). --------
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_trades_portfolio_id_trade_time
    ON trades (portfolio_id, trade_time);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_trades_trade_time
    ON trades (trade_time);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_market_data_ticker_trade_time
    ON market_data (ticker, trade_time);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_market_data_trade_time
    ON market_data (trade_time);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_audit_logs_trade_id_log_timestamp
    ON audit_logs (trade_id, log_timestamp);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_audit_logs_log_timestamp
    ON audit_logs (log_timestamp);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_audit_logs_event_type
    ON audit_logs (event_type);

-- 6. Refresh planner statistics so the new indexes get used immediately. ----
ANALYZE portfolios;
ANALYZE trades;
ANALYZE market_data;
ANALYZE audit_logs;
