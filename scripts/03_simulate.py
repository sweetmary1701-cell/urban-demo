#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
智慧交通可视化大屏 · 业务数据仿真器
================================================
把交通管理与事故处理所需的业务数据仿真出来并写入 PostGIS。

设计说明
--------
仿真模型（时段负荷曲线、拥堵系数、状态分布、事件类型权重）全部定义在本文件
的「仿真模型参数」一节，便于调参。而"沿 67k 条路段生成 N 个点"这类集合运算
交给 PostGIS 执行——用 SQL 是秒级，用 Python 逐行循环要几分钟。
因此这里是「Python 定义模型 + SQL 做集合生成」的混合方式。

用法:  .venv\\Scripts\\python.exe scripts\\03_simulate.py
"""
import asyncio
import random
from datetime import datetime

import asyncpg

DSN = "postgresql://postgres:postgres@localhost:5432/urban_demo"
random.seed(20261009)          # 固定随机种子 → 结果可复现

# ============================================================
#  仿真模型参数
# ============================================================

# 各路等级的自由流速度（km/h）
FREE_SPEED = {"高速": 120, "快速路": 80, "主干道": 60, "次干道": 40, "支路": 30}

# 全天 24 小时负荷曲线（1.0 = 自由流；早高峰 8 点、晚高峰 17 点）
LOAD = [0.50, 0.42, 0.38, 0.36, 0.40, 0.55,
        0.80, 1.10, 1.35, 1.00, 0.85, 0.88,
        0.92, 0.86, 0.82, 0.95, 1.15, 1.40,
        1.18, 0.95, 0.82, 0.72, 0.64, 0.56]

# 城市中心（姑苏区观前街一带），用于计算"城区拥堵加成"
CITY_CENTER = (120.6205, 31.3040)

SIGNAL_STATUS = [("正常", 0.955), ("警告", 0.028), ("故障", 0.017)]
SIGNAL_CYCLE = [90, 120, 140, 160, 180]

CAMERA_KIND = [("视频监控", 0.62), ("违法抓拍", 0.38)]
CAMERA_OFFLINE_RATE = 0.045

POLICE_KIND = [("交警大队", 0.05), ("中队", 0.22), ("铁骑", 0.35), ("巡逻车", 0.38)]
POLICE_STATUS = [("在岗", 0.62), ("出勤", 0.26), ("待命", 0.12)]

INCIDENT_KIND = [("交通事故", 0.57), ("车辆故障", 0.16), ("道路施工", 0.12),
                 ("异常拥堵", 0.10), ("积水", 0.05)]
INCIDENT_LEVEL = [("一般", 0.70), ("较重", 0.22), ("严重", 0.08)]
INCIDENT_STATUS = [("已完结", 0.44), ("处理中", 0.26), ("待处理", 0.30)]

VEHICLE_TYPE = [("小汽车", 0.72), ("货车", 0.10), ("公交车", 0.05),
                ("出租车", 0.06), ("网约车", 0.07)]

N_SIGNAL = 2600
N_CAMERA = 2200
N_POLICE = 180
N_INCIDENT = 320
MAJOR_CLASSES = ["高速", "快速路", "主干道", "次干道"]


# ---------- SQL 片段工具 ----------

def weighted(pairs):
    """按权重随机取一个名字（Python 侧用）"""
    return random.choices([p[0] for p in pairs], weights=[p[1] for p in pairs], k=1)[0]


def case_expr(pairs, col="random()"):
    """
    把累计概率映射成状态名的 SQL CASE 表达式。

    重要: col 必须是**同一行内固定的一个值**（通常是上层 CTE 里算好的
    random() 列）。绝不能直接传 random()——CASE 的每个 WHEN 会各自重新
    抽样，概率会连乘，结果完全错乱（曾经踩过：信号灯故障率 1.7% 变成了 0.08%）。
    """
    parts, acc = [], 0.0
    for name, p in pairs[:-1]:
        acc += p
        parts.append(f"WHEN {col} < {acc:.4f} THEN '{name}'")
    parts.append(f"ELSE '{pairs[-1][0]}'")
    return "CASE " + " ".join(parts) + " END"


def hour_load_sql(hour_expr="h.h"):
    """把 24 小时负荷数组转成按小时取值的 SQL CASE"""
    inner = " ".join(f"WHEN {hour_expr} = {h} THEN {v}" for h, v in enumerate(LOAD))
    return f"CASE {inner} ELSE 0.6 END"


def values_sql(pairs):
    """[('高速',120),...] -> "('高速',120),('快速路',80)" """
    return ",".join(f"('{k}',{v})" for k, v in pairs)


# 从 MultiLineString 上按比例取点：ST_LineInterpolatePoint 不接受多部件几何，
# 因此先 ST_GeometryN 取出第一条线
def lp(geom, frac):
    return f"ST_LineInterpolatePoint(ST_GeometryN({geom}, 1), {frac})"


CLASS_LOAD = """
CASE r.road_class
    WHEN '高速'   THEN 0.03 WHEN '快速路' THEN 0.25
    WHEN '主干道' THEN 0.38 WHEN '次干道' THEN 0.24
    ELSE 0.05 END
"""

# 拥堵等级阈值（路网拥堵指数 1.0~5.0）
LEVEL_THRESHOLDS = [(1.5, "畅通"), (2.0, "基本畅通"),
                    (2.8, "轻度拥堵"), (3.6, "中度拥堵")]

# 城市中心点（SQL 表达式），用于计算城区加成
CENTER_SQL = f"ST_SetSRID(ST_MakePoint({CITY_CENTER[0]}, {CITY_CENTER[1]}), 4326)"

FREE_SPEED_JOIN = f"""
JOIN (VALUES {values_sql(list(FREE_SPEED.items()))}) AS f(cls, v)
  ON f.cls = r.road_class
"""


# ============================================================
#  1. 交通信号灯 —— 在真实路口布设
# ============================================================
SQL_SIGNAL = f"""
WITH endpoints AS (
    -- 注意: ST_StartPoint/ST_EndPoint 只接受 LineString，对 MultiLineString 返回
    --       NULL，所以必须先用 ST_GeometryN(geom,1) 取出第一条线
    SELECT r.id AS road_id, r.district_id,
           unnest(ARRAY[
               ST_StartPoint(ST_GeometryN(r.geom, 1)),
               ST_EndPoint  (ST_GeometryN(r.geom, 1))
           ]) AS p
    FROM road r
    WHERE r.road_class = ANY(ARRAY['高速','快速路','主干道','次干道'])
      AND NOT ST_IsEmpty(r.geom)
),
junctions AS (
    -- 节点吸附到 ~30m 网格，同一格内有 2 条以上道路即视为一个路口
    SELECT ST_SnapToGrid(p, 0.0003)                       AS cell,
           count(DISTINCT road_id)                        AS n_road,
           (array_agg(road_id     ORDER BY road_id))[1]   AS road_id,
           (array_agg(district_id ORDER BY road_id))[1]   AS district_id
    FROM endpoints
    WHERE p IS NOT NULL
    GROUP BY 1
    HAVING count(DISTINCT road_id) >= 2
),
sampled AS (
    -- 抽样层：只做随机抽样，不生成属性
    SELECT * FROM junctions ORDER BY random() LIMIT {N_SIGNAL}
),
picked AS (
    -- 属性层：在新层级取随机值，否则会与上面的 ORDER BY random() 复用同一个数
    SELECT *, random() AS r_status FROM sampled
)
INSERT INTO signal (name, district_id, road_id, status, cycle_sec, geom)
SELECT coalesce(d.name, '市辖区') || '信号灯',
       p.district_id,
       p.road_id,
       {case_expr(SIGNAL_STATUS, "p.r_status")},
       (ARRAY[{",".join(map(str, SIGNAL_CYCLE))}])[1 + floor(random() * {len(SIGNAL_CYCLE)})::int],
       ST_SetSRID(p.cell, 4326)
FROM picked p
LEFT JOIN district d ON d.id = p.district_id;
"""

SQL_SIGNAL_CODE = """
UPDATE signal SET code = 'XF' || lpad(id::text, 5, '0') WHERE code IS NULL;
"""


# ============================================================
#  2. 视频监控 / 违法抓拍 —— 沿主干道以上按 ~700m 间距布设
# ============================================================
SQL_CAMERA = f"""
WITH candidates AS (
    SELECT r.id AS road_id, r.district_id,
           {lp("r.geom", "gs::float / greatest(2, ceil(r.length_m / 700) + 1)")} AS p
    FROM road r
    CROSS JOIN LATERAL generate_series(1, greatest(1, ceil(r.length_m / 700)::int)) gs
    WHERE r.road_class = ANY(ARRAY['高速','快速路','主干道','次干道'])
      AND r.length_m > 200
),
sampled AS (
    SELECT * FROM candidates ORDER BY random() LIMIT {N_CAMERA}
),
picked AS (
    SELECT *, random() AS r_kind FROM sampled
),
typed AS (
    SELECT p.*, {case_expr(CAMERA_KIND, "p.r_kind")} AS kind FROM picked p
)
INSERT INTO camera (name, kind, district_id, road_id, status, geom)
SELECT coalesce(d.name, '市辖区')
       || CASE t.kind WHEN '视频监控' THEN '监控点' ELSE '抓拍点' END,
       t.kind,
       t.district_id,
       t.road_id,
       CASE WHEN random() < {CAMERA_OFFLINE_RATE} THEN '离线' ELSE '在线' END,
       ST_SetSRID(t.p, 4326)
FROM typed t
LEFT JOIN district d ON d.id = t.district_id;
"""

SQL_CAMERA_CODE = """
UPDATE camera
SET code = CASE kind WHEN '视频监控' THEN 'JK' ELSE 'ZP' END || lpad(id::text, 5, '0')
WHERE code IS NULL;
"""


# ============================================================
#  3. 警力 —— 按行政区路网规模分配，落在辖区道路上
# ============================================================
SQL_POLICE = f"""
WITH dw AS (
    SELECT d.id, d.name, count(r.id) AS n_road
    FROM district d LEFT JOIN road r ON r.district_id = d.id
    GROUP BY d.id, d.name
),
alloc AS (
    SELECT id, name,
           greatest(3, round({N_POLICE} * n_road::numeric / sum(n_road) OVER ())::int) AS quota
    FROM dw
),
units AS (
    SELECT a.id AS district_id, a.name AS dname, g AS seq,
           random() AS r1, random() AS r2
    FROM alloc a CROSS JOIN LATERAL generate_series(1, a.quota) g
),
onroad AS (
    SELECT u.*, r.geom AS rgeom
    FROM units u
    JOIN LATERAL (
        SELECT geom FROM road WHERE district_id = u.district_id
        ORDER BY random() LIMIT 1
    ) r ON true
)
INSERT INTO police_unit (name, kind, district_id, status, officer_cnt, geom)
SELECT o.dname || {case_expr(POLICE_KIND, "o.r1")},
       {case_expr(POLICE_KIND, "o.r1")},
       o.district_id,
       {case_expr(POLICE_STATUS, "o.r2")},
       CASE WHEN o.r1 < 0.05 THEN 12 + floor(random() * 10)::int
            WHEN o.r1 < 0.27 THEN 6 + floor(random() * 6)::int
            ELSE 1 + floor(random() * 3)::int END,
       {lp("o.rgeom", "0.05 + random() * 0.9")}
FROM onroad o;
"""

SQL_POLICE_CODE = """
UPDATE police_unit SET code = 'JL' || lpad(id::text, 4, '0') WHERE code IS NULL;
"""


# ============================================================
#  4. 事件 / 事故 —— 沿路网加权随机分布
# ============================================================
SQL_INCIDENT = f"""
WITH cand AS (
    SELECT r.id AS road_id, r.name AS road_name, r.district_id, r.geom,
           -- 道路等级越高、越靠近市中心，事故概率越大
           CASE r.road_class
               WHEN '高速' THEN 3.0 WHEN '快速路' THEN 3.5 WHEN '主干道' THEN 2.5
               WHEN '次干道' THEN 1.6 WHEN '支路' THEN 1.0 ELSE 0.4 END
           * (1 + 2.0 * greatest(0, 1 - ST_Distance({lp("r.geom", "0.5")},
                                                    {CENTER_SQL}) * 111000 / 12000.0))
           AS cls_w
    FROM road r
    WHERE r.length_m > 60
),
pick AS (
    -- 加权随机抽样（指数竞赛法）：按权重分布选路，而不是只取权重最大的
    SELECT *, -ln(greatest(random(), 1e-9)) / greatest(cls_w, 0.05) AS key
    FROM cand
    ORDER BY key
    LIMIT {N_INCIDENT}
),
enriched AS (
    SELECT p.*,
           random() AS r_kind, random() AS r_level, random() AS r_status,
           random() AS r_ago,  random() AS r_dur,  random() AS r_police, random() AS r_pos
    FROM pick p
),
police_pick AS (
    SELECT id, district_id,
           row_number() OVER (PARTITION BY district_id ORDER BY random()) AS rn
    FROM police_unit
)
INSERT INTO incident (kind, level, status, district_id, road_id, road_name,
                      police_id, occurred_at, closed_at, geom)
SELECT {case_expr(INCIDENT_KIND, "e.r_kind")},
       {case_expr(INCIDENT_LEVEL, "e.r_level")},
       {case_expr(INCIDENT_STATUS, "e.r_status")},
       e.district_id, e.road_id, e.road_name,
       pp.id,
       now() - make_interval(mins => (e.r_ago * 1440)::int),
       CASE WHEN {case_expr(INCIDENT_STATUS, "e.r_status")} = '已完结'
            THEN now() - make_interval(mins => greatest(1, (e.r_ago * 1440
                                                          - 20 - e.r_dur * 60)::int))
            ELSE NULL END,
       ST_SetSRID({lp("e.geom", "0.05 + e.r_pos * 0.9")}, 4326)
FROM enriched e
LEFT JOIN police_pick pp
       ON pp.district_id = e.district_id
      AND pp.rn = 1 + floor(e.r_police * 3)::int;
"""

SQL_INCIDENT_CODE = """
UPDATE incident
SET code = 'SJ' || to_char(occurred_at, 'MMDD') || lpad(id::text, 4, '0')
WHERE code IS NULL;

-- 只有"处理中"的事件才占用警力
UPDATE incident SET police_id = NULL WHERE status = '待处理';
"""


# ============================================================
#  5. 路段实时状态 —— 拥堵指数 / 平均车速
# ============================================================
SQL_ROAD_STATUS = f"""
WITH base AS (
    SELECT r.id,
           f.v AS free_speed,
           coalesce(r.lanes, 2) AS lanes,
           ST_Distance({lp("r.geom", "0.5")}, {CENTER_SQL}) * 111000 AS dist_m,
           {CLASS_LOAD} AS cls_load,
           {hour_load_sql("extract(hour from now())::int")} AS hour_load,
           random() AS noise
    FROM road r
    {FREE_SPEED_JOIN}
),
hot AS (
    -- 单独一层取随机值：同一 SELECT 里写两个 random() 有被规划器合并的风险
    SELECT *, random() AS hot FROM base
),
calc AS (
    SELECT id, free_speed, lanes,
           least(5.0, greatest(1.0,
               1.0
               + cls_load
               + hour_load * 0.30                                  -- 当前时段负荷
               + greatest(0, 1 - dist_m / 7000.0) * 1.20           -- 城区加成
               + (noise - 0.5) * 0.80                              -- 随机波动
               -- 局部热点：严重拥堵主要发生在主/次干道与快速路上（事故、施工、瓶颈路段）
               + CASE WHEN hot < 0.020 AND cls_load >= 0.24 THEN 1.50 ELSE 0 END
           )) AS idx
    FROM hot
)
INSERT INTO road_status (road_id, speed_kmh, free_speed, congestion, level, flow_vph)
SELECT id,
       round((free_speed / idx)::numeric, 1),
       free_speed,
       round(idx::numeric, 2),
       CASE WHEN idx < {LEVEL_THRESHOLDS[0][0]} THEN '{LEVEL_THRESHOLDS[0][1]}'
            WHEN idx < {LEVEL_THRESHOLDS[1][0]} THEN '{LEVEL_THRESHOLDS[1][1]}'
            WHEN idx < {LEVEL_THRESHOLDS[2][0]} THEN '{LEVEL_THRESHOLDS[2][1]}'
            WHEN idx < {LEVEL_THRESHOLDS[3][0]} THEN '{LEVEL_THRESHOLDS[3][1]}'
            ELSE '严重拥堵' END,
       least(1900, greatest(40,
             round((free_speed / idx) * lanes * 22 * (0.85 + random() * 0.3))::int))
FROM calc;
"""


# ============================================================
#  6. 时序流量 —— 近 24 小时 × 主干道以上
# ============================================================
SQL_TRAFFIC_FLOW = f"""
WITH hours AS (SELECT generate_series(0, 23) AS h),
rb AS (
    SELECT r.id AS road_id, f.v AS free_speed, {CLASS_LOAD} AS cls_load
    FROM road r
    {FREE_SPEED_JOIN}
    WHERE r.road_class = ANY(ARRAY['高速','快速路','主干道','次干道'])
),
gen AS (
    -- 先生成时间戳，再按时间戳的**真实钟点**取负荷值，
    -- 否则负荷曲线会和墙上时钟错位（曾经峰值出现在凌晨 5 点）
    SELECT b.road_id, b.free_speed, b.cls_load,
           date_trunc('hour', now()) - make_interval(hours => 23 - h.h) AS ts
    FROM rb b CROSS JOIN hours h
)
INSERT INTO traffic_flow (road_id, ts, flow_vph, speed_kmh, congestion)
SELECT road_id, g.ts,
       round(free_speed * {hour_load_sql("extract(hour from g.ts)::int")}
             * (1.5 + random() * 0.4) * 11)::int,
       round((free_speed
              / least(5.0, 1 + cls_load
                      + {hour_load_sql("extract(hour from g.ts)::int")} * 0.9
                      + random() * 0.3))::numeric, 1),
       round(least(5.0, 1 + cls_load
                   + {hour_load_sql("extract(hour from g.ts)::int")} * 0.9
                   + random() * 0.3)::numeric, 2)
FROM gen g;
"""


# ============================================================
#  7. 区域车辆分布 —— 行政区 × 24 小时 × 车型
# ============================================================
SQL_DISTRICT_VEHICLE = f"""
WITH hours AS (SELECT generate_series(0, 23) AS h),
dw AS (
    SELECT d.id, count(r.id) AS n_road, d.area_km2
    FROM district d LEFT JOIN road r ON r.district_id = d.id
    GROUP BY d.id, d.area_km2
),
norm AS (
    SELECT id,
           greatest(1, round(
              40000
              * (area_km2 / sum(area_km2) OVER ())
              * (0.7 + n_road::numeric / max(n_road) OVER () * 0.6)
           )::int) AS base_cnt
    FROM dw
),
gen AS (
    SELECT n.id AS district_id, n.base_cnt,
           date_trunc('hour', now()) - make_interval(hours => 23 - h.h) AS ts
    FROM norm n CROSS JOIN hours h
),
vt AS (
    SELECT * FROM (VALUES {values_sql(VEHICLE_TYPE)}) AS t(name, ratio)
)
INSERT INTO district_vehicle (district_id, ts, vehicle_type, cnt)
SELECT g.district_id,
       g.ts,
       vt.name,
       greatest(1, round(g.base_cnt
                         * {hour_load_sql("extract(hour from g.ts)::int")}
                         * vt.ratio * (0.9 + random() * 0.2))::int)
FROM gen g CROSS JOIN vt;
"""


async def run_step(conn, no, title, sql):
    print(f"\n===== {no}. {title} =====")
    t0 = datetime.now()
    result = await conn.execute(sql)
    rows = result.split()[-1] if result and result.split() else "?"
    print(f"  {result}   用时 {(datetime.now() - t0).total_seconds():.1f}s")
    return rows


async def main():
    print("目标库:", DSN.split("@")[-1])
    conn = await asyncpg.connect(DSN)
    try:
        print("\n清理旧仿真数据（可重复执行）...")
        await conn.execute("""
            TRUNCATE signal, camera, police_unit, incident,
                     road_status, traffic_flow, district_vehicle
            RESTART IDENTITY CASCADE;
        """)
        print("  完成")

        await run_step(conn, 1, f"交通信号灯（真实路口布设，上限 {N_SIGNAL}）", SQL_SIGNAL)
        await conn.execute(SQL_SIGNAL_CODE)
        await run_step(conn, 2, f"视频监控 / 违法抓拍（{N_CAMERA}）", SQL_CAMERA)
        await conn.execute(SQL_CAMERA_CODE)
        await run_step(conn, 3, f"警力（目标 {N_POLICE}，按行政区路网规模分配）", SQL_POLICE)
        await conn.execute(SQL_POLICE_CODE)
        await run_step(conn, 4, f"事件 / 事故（{N_INCIDENT}）", SQL_INCIDENT)
        await conn.execute(SQL_INCIDENT_CODE)
        await run_step(conn, 5, "路段实时状态（全部路网）", SQL_ROAD_STATUS)
        await run_step(conn, 6, "时序流量（近 24h × 主干道以上）", SQL_TRAFFIC_FLOW)
        await run_step(conn, 7, "区域车辆分布（行政区 × 24h × 车型）", SQL_DISTRICT_VEHICLE)

        print("\n" + "=" * 64)
        print("仿真结果概览")
        print("=" * 64)

        r = await conn.fetchrow("""
            SELECT count(*) AS total,
                   count(*) FILTER (WHERE status = '正常') AS ok,
                   count(*) FILTER (WHERE status = '故障') AS bad,
                   count(*) FILTER (WHERE status = '警告') AS warn
            FROM signal
        """)
        print(f"  信号灯  {r['total']} 个   正常 {r['ok']} / 故障 {r['bad']} / 警告 {r['warn']}")

        r = await conn.fetchrow("""
            SELECT count(*) AS total,
                   count(*) FILTER (WHERE kind = '视频监控') AS cam,
                   count(*) FILTER (WHERE kind = '违法抓拍') AS snap,
                   count(*) FILTER (WHERE status = '离线') AS off
            FROM camera
        """)
        print(f"  监控设备 {r['total']} 个   视频监控 {r['cam']} / 违法抓拍 {r['snap']} / 离线 {r['off']}")

        for label, sql in [
            ("警力状态", "SELECT status AS k, count(*)::text AS v FROM police_unit GROUP BY 1 ORDER BY 2 DESC"),
            ("事件类型", "SELECT kind AS k, count(*)::text AS v FROM incident GROUP BY 1 ORDER BY 2 DESC"),
            ("事件状态", "SELECT status AS k, count(*)::text AS v FROM incident GROUP BY 1 ORDER BY 2 DESC"),
            ("拥堵等级", "SELECT level AS k, count(*)::text AS v FROM road_status GROUP BY 1 ORDER BY 2 DESC"),
        ]:
            recs = await conn.fetch(sql)
            print(f"  {label}: " + " | ".join(f"{x['k']}={x['v']}" for x in recs))

        n_flow = await conn.fetchval("SELECT count(*) FROM traffic_flow")
        n_veh = await conn.fetchval("SELECT count(*) FROM district_vehicle")
        print(f"  时序流量 {n_flow:,} 行 / 区域车辆 {n_veh:,} 行")

        print("\n各行政区事件分布:")
        recs = await conn.fetch("""
            SELECT d.name,
                   (SELECT count(*) FROM incident i WHERE i.district_id = d.id) AS incidents,
                   (SELECT round(sum(r.length_m) / 1000) FROM road r
                     WHERE r.district_id = d.id)                                    AS road_km,
                   (SELECT count(*) FROM signal s WHERE s.district_id = d.id)     AS signals
            FROM district d
            ORDER BY incidents DESC
        """)
        for x in recs:
            density = (x["incidents"] / x["road_km"] * 100) if x["road_km"] else 0
            print(f"    {x['name']:<10} 事件 {x['incidents']:>3}   "
                  f"路网 {str(x['road_km']):>5} km   信号灯 {x['signals']:>4}   "
                  f"事故密度 {density:.2f}/百km")

    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())
