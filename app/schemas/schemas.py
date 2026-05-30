from pydantic import BaseModel
from typing import List, Dict
class TradeSummary(BaseModel):
    ticker: str
    side: str
    amount: float
    price: float
class TradeOut(TradeSummary):
    id: int
    portfolio_id: int
    trade_time: str
    status: str
class AuditLogOut(BaseModel):
    id: int
    event_type: str
    log_timestamp: str
    event_data: Dict
class PortfolioSummary(BaseModel):
    portfolio_id: int
    total_trades: int
    total_amount: float
    tickers: List[str]