# Baseline snapshot — before code deploy + NUMERIC/constraint migration

Captured against live server `64.227.178.86` (`tradingdb`).
State at capture: **indexes already applied**, but **original app code still running** and
columns still **FLOAT8**, no NOT NULL / UNIQUE constraints.

## Endpoint timings (5 samples)
| Endpoint | Samples | Notes |
|---|---|---|
| `GET /api/portfolio/1/summary` | 0.109 / 0.027 / 0.021 / 0.035 / 0.026 s | first call warms cache; Python-side aggregation |
| `GET /api/audit/42` | ~0.005 s | already index-served |

## Endpoint bodies
- `summary/1`: `total_trades=1667, total_amount=81382.27856747576, tickers=[GOOG,AAPL,TSLA]`
- `summary/2`: `total_trades=1667, total_amount=87041.87848047275, tickers=[GOOG,AAPL]`
  (TSLA in pf 1 = the test trade id 5001 added during diagnosis.)

## Query plans
- summary aggregation: **Seq Scan** on trades, 1667 of 5001 rows, exec ~1.69 ms
  (seq scan is correct at this cardinality: pf 1 = 1/3 of table; index wins only when a
  portfolio is a small fraction, i.e. at real scale)
- audit lookup: **Index Scan Backward** using `ix_audit_logs_trade_id_log_timestamp`, exec ~0.15 ms

## Schema (before)
- `trades.amount` = double precision, `trades.price` = double precision
- `market_data.price/volume` = double precision
- `trades.portfolio_id` = bigint (NULLABLE), `audit_logs.trade_id` = bigint (NULLABLE), `trades.side` = varchar (NULLABLE)
- Constraints: only FKs `trades_portfolio_id_fkey`, `audit_logs_trade_id_fkey`. **No UNIQUE(owner,name).**
- Indexes: 7 custom indexes already present (applied in the indexes-first step).

## Data snapshot (before)
- Row counts: trades=5001, audit_logs=2001, market_data=5000, portfolios=3
- Sample trades: `1: amount=90.73189701312057 price=405.69932860661964` · `2: 23.703954523546834 / 514.6934245461694` · `3: 15.482087959507695 / 1091.2722678106484` · `5001: 10 / 250`
- Checksums: `sum_amount=252968.34675817977`, `sum_price=3014186.728730389`
- Audit coverage: 2001 trades have an audit row (seed only logged ids 1..2000 + test trade 5001)

## ⚠ Expected effect of NUMERIC(20,4) conversion (NOT corruption)
Money columns round to 4 decimal places (correct for a ledger):
- `1: 90.73189701312057 -> 90.7319 | 405.69932860661964 -> 405.6993`
- `2: 23.703954523546834 -> 23.7040 | 514.6934245461694 -> 514.6934`
- `3: 15.482087959507695 -> 15.4821 | 1091.2722678106484 -> 1091.2723`
- `sum_amount: 252968.34675817977 -> 252968.3480` (≈0.001 shift from rounding 5001 values)

So `summary` totals will shift by sub-cent rounding after migration — expected, not a bug.

---

# After deploy

State: NUMERIC/constraint migration applied + API restarted (new code live).

## Endpoint timings (5 samples) — before → after
| Endpoint | Before (steady) | After (steady) | Change |
|---|---|---|---|
| `GET /api/portfolio/1/summary` | ~0.021–0.035 s | ~0.007–0.009 s | ~3–4× faster (SQL aggregation vs Python loop over 1667 rows) |
| `GET /api/audit/42` | ~0.005 s | ~0.005–0.006 s | unchanged (already index-served) |

(Steady-state excludes the first warm-up call. At 5k rows the gap is small; it widens with row count — Python aggregation is O(rows) in transfer+memory, SQL aggregation returns one row.)

## Endpoint bodies — before → after
| | Before | After | Note |
|---|---|---|---|
| summary/1 total_amount | 81382.27856747576 | 81382.2779 | 4dp rounding (NUMERIC) |
| summary/2 total_amount | 87041.87848047275 | 87041.879 | 4dp rounding |
| tickers | correct | correct | unchanged |

## Query plans — before → after
- summary: Seq Scan → Seq Scan (correct: pf 1 = 1/3 of table; index only wins when a portfolio is a small fraction, i.e. real scale). Exec ~1.7 ms → ~1.3 ms.
- audit: Index Scan Backward → Index Scan Backward (unchanged; index added in step 1). Exec ~0.15 ms → ~0.18 ms.

## Schema — before → after
| Item | Before | After |
|---|---|---|
| trades.amount / price | double precision | **numeric(20,4)** |
| market_data.price / volume | double precision | **numeric(20,4)** |
| trades.portfolio_id | bigint NULL | bigint **NOT NULL** |
| trades.side | varchar NULL | varchar **NOT NULL** |
| audit_logs.trade_id | bigint NULL | bigint **NOT NULL** |
| trades.amount / price NOT NULL | no | **yes** (applied to live DB; also in migrate.sql) |
| UNIQUE(owner,name) | absent | **present** (uq_portfolios_owner_name) |
| FK on-delete | default | **RESTRICT** (fk_trades_portfolio, fk_audit_logs_trade) |
| custom indexes | 7 (step 1) | 7 (valid) |

## Data integrity — before → after
| | Before | After |
|---|---|---|
| trades / audit_logs / market_data counts | 5001 / 2001 / 5000 | 5001 / 2001 / 5000 (unchanged) |
| sum_amount | 252968.34675817977 | 252968.3480 (= predicted rounded) |
| sum_price | 3014186.728730389 | 3014186.7314 (rounded) |

No data loss — only the intended 4dp money rounding.

## Atomic audit — new behavior verified
POST trade 5002 (NVDA) → audit row 2002 written in the SAME transaction, confirmed in DB,
with enriched event_data `{ticker, side}`. A trade can no longer commit without its audit row.

## Connection pool
150 max (pool_size 50 + overflow 100, exceeded Postgres max_connections=100) → 30 max
(pool_size 20 + overflow 10) + pool_pre_ping + pool_recycle.
