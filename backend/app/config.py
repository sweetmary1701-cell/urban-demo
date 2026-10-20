"""后端配置（业务接口服务）"""
import os

# 数据库（与 scripts/03_simulate.py、GeoServer 数据源保持一致）
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/urban_demo",
)

# 允许跨域的前端地址（Vite 开发服务器）
CORS_ORIGINS = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
]
