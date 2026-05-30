from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, declarative_base
DATABASE_URL = "postgresql+asyncpg://traderadmin:tradepass2024@postgres:5432/tradingdb"
Base = declarative_base()
engine = create_async_engine(DATABASE_URL, pool_size=50, max_overflow=100, echo=False)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, autoflush=False, expire_on_commit=False)
async def get_db():
    async with AsyncSessionLocal() as session:
        yield session