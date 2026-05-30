from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, BigInteger, JSON, Index
from sqlalchemy.orm import relationship
from app.database import Base
class Portfolio(Base):
    __tablename__ = 'portfolios'
    id = Column(BigInteger, primary_key=True)
    owner = Column(String(100), nullable=False)
    name = Column(String(100), nullable=False)
    trades = relationship('Trade', back_populates='portfolio')

class Trade(Base):
    __tablename__ = 'trades'
    id = Column(BigInteger, primary_key=True)
    portfolio_id = Column(BigInteger, ForeignKey('portfolios.id'))
    ticker = Column(String(16), nullable=False)
    side = Column(String(8), nullable=False)
    amount = Column(Float, nullable=False)
    price = Column(Float, nullable=False)
    trade_time = Column(DateTime, nullable=False)
    status = Column(String(16))
    portfolio = relationship('Portfolio', back_populates='trades')
    audit_logs = relationship('AuditLog', back_populates='trade')

class MarketData(Base):
    __tablename__ = 'market_data'
    id = Column(BigInteger, primary_key=True)
    ticker = Column(String(16), nullable=False)
    trade_time = Column(DateTime, nullable=False)
    price = Column(Float, nullable=False)
    volume = Column(Float, nullable=False)
    extra_json = Column(JSON)

class AuditLog(Base):
    __tablename__ = 'audit_logs'
    id = Column(BigInteger, primary_key=True)
    trade_id = Column(BigInteger, ForeignKey('trades.id'), nullable=True)
    event_type = Column(String(32), nullable=False)
    event_data = Column(JSON, nullable=False)
    log_timestamp = Column(DateTime, nullable=False)
    trade = relationship('Trade', back_populates='audit_logs')

# Deliberately sub-optimal / missing indexes for performance troubleshooting:
# (No composite indexes, missing timestamp/ticker indexes, no partial indexes, and nullable foreign keys)