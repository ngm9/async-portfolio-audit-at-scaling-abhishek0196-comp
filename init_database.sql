-- Normalized, constrained, indexed schema for a high-volume trading OLTP+OLAP app.
-- Fresh-install DDL (matches app/models/models.py). For an existing populated
-- database, run migrate.sql instead (it converts in place without data loss).

CREATE TABLE portfolios (
    id BIGSERIAL PRIMARY KEY,
    owner VARCHAR(100) NOT NULL,
    name VARCHAR(100) NOT NULL,
    CONSTRAINT uq_portfolios_owner_name UNIQUE (owner, name)
);

CREATE TABLE trades (
    id BIGSERIAL PRIMARY KEY,
    portfolio_id BIGINT NOT NULL,
    ticker VARCHAR(16) NOT NULL,
    side VARCHAR(8) NOT NULL,
    -- Exact decimal money/quantity, never binary FLOAT, for a financial ledger.
    amount NUMERIC(20, 4) NOT NULL,
    price NUMERIC(20, 4) NOT NULL,
    trade_time TIMESTAMP NOT NULL,
    status VARCHAR(16),
    CONSTRAINT fk_trades_portfolio FOREIGN KEY (portfolio_id)
        REFERENCES portfolios (id) ON DELETE RESTRICT
);
-- Portfolio summary + portfolio-scoped time-range reporting.
CREATE INDEX ix_trades_portfolio_id_trade_time ON trades (portfolio_id, trade_time);
-- EOD / cross-portfolio time scans.
CREATE INDEX ix_trades_trade_time ON trades (trade_time);

CREATE TABLE market_data (
    id BIGSERIAL PRIMARY KEY,
    ticker VARCHAR(16) NOT NULL,
    trade_time TIMESTAMP NOT NULL,
    price NUMERIC(20, 4) NOT NULL,
    volume NUMERIC(20, 4) NOT NULL,
    extra_json JSON
);
CREATE INDEX ix_market_data_ticker_trade_time ON market_data (ticker, trade_time);
CREATE INDEX ix_market_data_trade_time ON market_data (trade_time);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    trade_id BIGINT NOT NULL,
    event_type VARCHAR(32) NOT NULL,
    event_data JSON NOT NULL,
    log_timestamp TIMESTAMP NOT NULL,
    CONSTRAINT fk_audit_logs_trade FOREIGN KEY (trade_id)
        REFERENCES trades (id) ON DELETE RESTRICT
);
-- /audit/{trade_id}: WHERE trade_id = ? ORDER BY log_timestamp DESC.
CREATE INDEX ix_audit_logs_trade_id_log_timestamp ON audit_logs (trade_id, log_timestamp);
-- Time-range compliance reporting across all trades.
CREATE INDEX ix_audit_logs_log_timestamp ON audit_logs (log_timestamp);
-- Compliance reporting grouped/filtered by event type.
CREATE INDEX ix_audit_logs_event_type ON audit_logs (event_type);

-- Seed portfolios
INSERT INTO portfolios (owner, name) VALUES ('alice', 'growth'), ('bob', 'value'), ('carol', 'daytrade');

-- Seed trades and market_data
DO $$
DECLARE
  i int;
  p int;
  t text;
BEGIN
  FOR i IN 1..5000 LOOP
    p := (i % 3) + 1;
    t := CASE WHEN (i % 2) = 0 THEN 'AAPL' ELSE 'GOOG' END;
    INSERT INTO trades (portfolio_id, ticker, side, amount, price, trade_time, status) VALUES (p, t, 'buy', RANDOM()*100, RANDOM()*1000+100, NOW() - (i || ' minutes')::interval, 'executed');
    INSERT INTO market_data (ticker, trade_time, price, volume, extra_json) VALUES (t, NOW() - (i || ' minutes')::interval, RANDOM()*1000+100, RANDOM()*1000, '{"vol": "test"}');
  END LOOP;
END$$;

-- Seed audit logs (trade_id now references real, existing trades 1..2000)
DO $$
DECLARE
  i int;
  e text;
BEGIN
  FOR i IN 1..2000 LOOP
    e := CASE WHEN (i % 2) = 0 THEN 'TRADE_EXECUTED' ELSE 'TRADE_CANCEL' END;
    INSERT INTO audit_logs (trade_id, event_type, event_data, log_timestamp) VALUES (i, e, '{"msg": "Test log"}', NOW() - (i || ' seconds')::interval);
  END LOOP;
END$$;

ANALYZE portfolios;
ANALYZE trades;
ANALYZE market_data;
ANALYZE audit_logs;
