from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, declarative_base
DATABASE_URL = "postgresql+asyncpg://traderadmin:tradepass2024@postgres:5432/tradingdb"
Base = declarative_base()
# Keep total connections (pool_size + max_overflow) well under Postgres'
# default max_connections=100; the old 50+100=150 ceiling exhausted the server
# under load. pool_pre_ping drops dead connections; pool_recycle avoids stale
# ones being handed to the event loop.
engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
    pool_recycle=1800,
    echo=False,
)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, autoflush=False, expire_on_commit=False)
async def get_db():
    async with AsyncSessionLocal() as session:
        yield session