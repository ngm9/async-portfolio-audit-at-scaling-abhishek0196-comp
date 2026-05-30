from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func
from app.database import get_db
from app.models.models import Trade, AuditLog
from app.schemas.schemas import TradeSummary, TradeOut, AuditLogOut, PortfolioSummary
import datetime

router = APIRouter()


@router.get("/portfolio/{portfolio_id}/summary", response_model=PortfolioSummary)
async def get_portfolio_summary(portfolio_id: int, db: AsyncSession = Depends(get_db)):
    # Aggregate in Postgres (one row over the index) instead of pulling every
    # trade into Python — keeps memory flat and never blocks the event loop.
    res = await db.execute(
        select(
            func.count(Trade.id),
            func.coalesce(func.sum(Trade.amount), 0),
            func.array_agg(func.distinct(Trade.ticker)),
        ).where(Trade.portfolio_id == portfolio_id)
    )
    total_trades, total_amount, tickers = res.one()
    return PortfolioSummary(
        portfolio_id=portfolio_id,
        total_trades=total_trades or 0,
        total_amount=float(total_amount or 0),
        tickers=[t for t in (tickers or []) if t is not None],
    )


@router.post("/portfolio/{portfolio_id}/trade", response_model=TradeOut)
async def make_trade(
    portfolio_id: int, trade: TradeSummary, db: AsyncSession = Depends(get_db)
):
    # Trade + its audit record are written in a SINGLE transaction, so a trade
    # can never be persisted without its compliance audit entry (no gaps), and
    # any failure rolls both back atomically (ACID).
    now = datetime.datetime.utcnow()
    t = Trade(
        portfolio_id=portfolio_id,
        ticker=trade.ticker,
        side=trade.side,
        amount=trade.amount,
        price=trade.price,
        trade_time=now,
        status="executed",
    )
    db.add(t)
    await db.flush()  # assigns t.id without committing

    db.add(
        AuditLog(
            trade_id=t.id,
            event_type="TRADE_EXECUTED",
            event_data={"msg": "Executed trade", "ticker": t.ticker, "side": t.side},
            log_timestamp=now,
        )
    )

    try:
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Trade could not be recorded")

    await db.refresh(t)
    return TradeOut(
        id=t.id,
        ticker=t.ticker,
        portfolio_id=t.portfolio_id,
        side=t.side,
        amount=float(t.amount),
        price=float(t.price),
        trade_time=str(t.trade_time),
        status=t.status,
    )


@router.get("/audit/{trade_id}", response_model=list[AuditLogOut])
async def get_audit_logs(trade_id: int, db: AsyncSession = Depends(get_db)):
    # Served by ix_audit_logs_trade_id_log_timestamp (filter + ordered sort).
    q = await db.execute(
        select(AuditLog)
        .where(AuditLog.trade_id == trade_id)
        .order_by(AuditLog.log_timestamp.desc())
    )
    logs = q.scalars().all()
    return [
        AuditLogOut(
            id=l.id,
            event_type=l.event_type,
            log_timestamp=str(l.log_timestamp),
            event_data=l.event_data,
        )
        for l in logs
    ]
