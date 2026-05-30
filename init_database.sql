-- Deliberately suboptimal, denormalized schema and missing indexes for high-volume trading OLTP+OLAP app
CREATE TABLE portfolios (
    id BIGSERIAL PRIMARY KEY,
    owner VARCHAR(100) NOT NULL,
    name VARCHAR(100) NOT NULL
    -- no unique(owner, name) constraint
);
CREATE TABLE trades (
    id BIGSERIAL PRIMARY KEY,
    portfolio_id BIGINT,
    ticker VARCHAR(16) NOT NULL,
    side VARCHAR(8),
    amount FLOAT8,
    price FLOAT8,
    trade_time TIMESTAMP NOT NULL,
    status VARCHAR(16),
    FOREIGN KEY(portfolio_id) REFERENCES portfolios(id)
);
CREATE TABLE market_data (
    id BIGSERIAL PRIMARY KEY,
    ticker VARCHAR(16) NOT NULL,
    trade_time TIMESTAMP NOT NULL,
    price FLOAT8,
    volume FLOAT8,
    extra_json JSON
    -- no index on trade_time or ticker
);
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    trade_id BIGINT,
    event_type VARCHAR(32),
    event_data JSON NOT NULL,
    log_timestamp TIMESTAMP NOT NULL,
    FOREIGN KEY(trade_id) REFERENCES trades(id)
    -- no index on trade_id or log_timestamp, allows NULLs
);
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
-- Seed incomplete audit logs
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
