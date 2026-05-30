from sqlalchemy import (
    Column,
    String,
    ForeignKey,
    DateTime,
    BigInteger,
    Numeric,
    JSON,
    Index,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship
from app.database import Base


class Portfolio(Base):
    __tablename__ = 'portfolios'
    id = Column(BigInteger, primary_key=True)
    owner = Column(String(100), nullable=False)
    name = Column(String(100), nullable=False)
    trades = relationship('Trade', back_populates='portfolio')

    __table_args__ = (
        # A given owner cannot have two portfolios with the same name.
        UniqueConstraint('owner', 'name', name='uq_portfolios_owner_name'),
    )


class Trade(Base):
    __tablename__ = 'trades'
    id = Column(BigInteger, primary_key=True)
    # Every trade MUST belong to a portfolio (no orphan trades).
    portfolio_id = Column(
        BigInteger, ForeignKey('portfolios.id', ondelete='RESTRICT'), nullable=False
    )
    ticker = Column(String(16), nullable=False)
    side = Column(String(8), nullable=False)
    # Money/quantity as exact NUMERIC, never binary FLOAT, for a financial ledger.
    amount = Column(Numeric(20, 4), nullable=False)
    price = Column(Numeric(20, 4), nullable=False)
    trade_time = Column(DateTime, nullable=False)
    status = Column(String(16))
    portfolio = relationship('Portfolio', back_populates='trades')
    audit_logs = relationship('AuditLog', back_populates='trade')

    __table_args__ = (
        # Hot path: /portfolio/{id}/summary filters/aggregates by portfolio_id.
        # Composite also serves portfolio-scoped time-range reporting.
        Index('ix_trades_portfolio_id_trade_time', 'portfolio_id', 'trade_time'),
        # EOD / cross-portfolio reporting scans by time.
        Index('ix_trades_trade_time', 'trade_time'),
    )


class MarketData(Base):
    __tablename__ = 'market_data'
    id = Column(BigInteger, primary_key=True)
    ticker = Column(String(16), nullable=False)
    trade_time = Column(DateTime, nullable=False)
    price = Column(Numeric(20, 4), nullable=False)
    volume = Column(Numeric(20, 4), nullable=False)
    extra_json = Column(JSON)

    __table_args__ = (
        # EOD pricing/risk lookups are per-ticker over a time window.
        Index('ix_market_data_ticker_trade_time', 'ticker', 'trade_time'),
        Index('ix_market_data_trade_time', 'trade_time'),
    )


class AuditLog(Base):
    __tablename__ = 'audit_logs'
    id = Column(BigInteger, primary_key=True)
    # Audit rows always reference a trade; written atomically with the trade.
    trade_id = Column(
        BigInteger, ForeignKey('trades.id', ondelete='RESTRICT'), nullable=False
    )
    event_type = Column(String(32), nullable=False)
    event_data = Column(JSON, nullable=False)
    log_timestamp = Column(DateTime, nullable=False)
    trade = relationship('Trade', back_populates='audit_logs')

    __table_args__ = (
        # /audit/{trade_id} filters by trade_id and ORDER BY log_timestamp DESC.
        Index('ix_audit_logs_trade_id_log_timestamp', 'trade_id', 'log_timestamp'),
        # Time-range compliance reporting across all trades.
        Index('ix_audit_logs_log_timestamp', 'log_timestamp'),
        # Compliance reporting grouped/filtered by event type.
        Index('ix_audit_logs_event_type', 'event_type'),
    )
