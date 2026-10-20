"""
苏州智慧交通可视化大屏 · 业务数据接口
========================================
职责边界：本服务只提供**业务统计接口**（指标卡、图表、排行）。
地理数据的发布（WMS 出图 / SLD 样式 / 属性查询）由 GeoServer 承担，
两者共用同一个 PostGIS 数据库。

启动:
    .venv\\Scripts\\python.exe -m uvicorn backend.app.main:app --reload --port 8000
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from . import db, stats
from .config import CORS_ORIGINS


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.init_pool()
    yield
    await db.close_pool()


app = FastAPI(title="苏州智慧交通可视化大屏 API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def fetch_all(sql: str, *args):
    async with db.pool().acquire() as conn:
        return [dict(r) for r in await conn.fetch(sql, *args)]


async def fetch_one(sql: str, *args):
    async with db.pool().acquire() as conn:
        row = await conn.fetchrow(sql, *args)
        return dict(row) if row else None


# ============================================================
#  健康检查
# ============================================================
@app.get("/api/health")
async def health():
    async with db.pool().acquire() as conn:
        n = await conn.fetchval("SELECT count(*) FROM road")
    return {"status": "ok", "roads": n}


# ============================================================
#  总览：一次拿齐所有面板需要的汇总指标
# ============================================================
@app.get("/api/overview")
async def overview():
    return {
        "road_classes": await fetch_all(stats.ROAD_CLASS),
        "congestion": await fetch_one(stats.CONGESTION),
        "signal": await fetch_one(stats.SIGNAL),
        "camera": await fetch_one(stats.CAMERA),
        "police": await fetch_one(stats.POLICE),
        "police_by_kind": await fetch_all(stats.POLICE_BY_KIND),
        "incident": await fetch_one(stats.INCIDENT),
        "incident_by_kind": await fetch_all(stats.INCIDENT_BY_KIND),
    }


# ============================================================
#  趋势 / 分区 / 车辆 / 事件
# ============================================================
@app.get("/api/trend")
async def trend():
    return await fetch_all(stats.TREND)


@app.get("/api/districts")
async def districts():
    return await fetch_all(stats.DISTRICT_HEAT)


@app.get("/api/vehicles")
async def vehicles():
    return {
        "by_type": await fetch_all(stats.VEHICLE_BY_TYPE),
        "by_district": await fetch_all(stats.VEHICLE_BY_DISTRICT),
    }


@app.get("/api/incidents/recent")
async def incidents_recent(limit: int = Query(12, ge=1, le=100)):
    return await fetch_all(stats.INCIDENT_RECENT, limit)


@app.get("/api/metro/lines")
async def metro_lines():
    """地铁线路清单（前端据此生成线路开关）"""
    return await fetch_all(stats.METRO_LINES)


@app.get("/api/transit/summary")
async def transit_summary():
    """轨道 + 公交的总体规模"""
    return {
        "totals": await fetch_one(stats.TRANSIT_SUMMARY),
        "bus_networks": await fetch_all(stats.BUS_NETWORKS),
    }


