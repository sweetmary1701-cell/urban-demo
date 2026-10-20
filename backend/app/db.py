"""数据库连接池"""
import asyncpg

from .config import DATABASE_URL

_pool: asyncpg.Pool | None = None


async def init_pool() -> None:
    global _pool
    _pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=12)


async def close_pool() -> None:
    global _pool
    if _pool:
        await _pool.close()
        _pool = None


def pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("数据库连接池尚未初始化")
    return _pool
