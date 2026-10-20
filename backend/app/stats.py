"""统计查询：大屏各面板所需的聚合数据"""

# 各路等级的数量与里程
ROAD_CLASS = """
SELECT road_class AS class, count(*)::int AS count,
       round(sum(length_m) / 1000)::int AS km
FROM road
GROUP BY road_class
ORDER BY CASE road_class
             WHEN '高速' THEN 1 WHEN '快速路' THEN 2 WHEN '主干道' THEN 3
             WHEN '次干道' THEN 4 ELSE 5 END
"""

# 整体拥堵概况
CONGESTION = """
SELECT count(*)::int                                                    AS total,
       count(*) FILTER (WHERE level IN ('中度拥堵', '严重拥堵'))::int    AS congested,
       count(*) FILTER (WHERE level = '严重拥堵')::int                  AS severe,
       round(avg(congestion), 2)                                        AS avg_index,
       round(avg(speed_kmh), 1)                                         AS avg_speed
FROM road_status
"""

# 交通信号
SIGNAL = """
SELECT count(*)::int                                     AS total,
       count(*) FILTER (WHERE status = '正常')::int       AS ok,
       count(*) FILTER (WHERE status = '故障')::int       AS fault,
       count(*) FILTER (WHERE status = '警告')::int       AS warn
FROM signal
"""

# 视频监控 / 违法抓拍
CAMERA = """
SELECT count(*)::int                                          AS total,
       count(*) FILTER (WHERE kind = '视频监控')::int          AS monitor,
       count(*) FILTER (WHERE kind = '违法抓拍')::int          AS violation,
       count(*) FILTER (WHERE status = '离线')::int            AS offline
FROM camera
"""

# 警力
POLICE = """
SELECT count(*)::int                                       AS total,
       coalesce(sum(officer_cnt), 0)::int                  AS officers,
       count(*) FILTER (WHERE status = '在岗')::int         AS on_duty,
       count(*) FILTER (WHERE status = '出勤')::int         AS dispatched,
       count(*) FILTER (WHERE status = '待命')::int         AS standby
FROM police_unit
"""

POLICE_BY_KIND = """
SELECT kind, count(*)::int AS cnt FROM police_unit GROUP BY kind ORDER BY cnt DESC
"""

# 事件 / 事故
INCIDENT = """
SELECT count(*)::int                                       AS total,
       count(*) FILTER (WHERE status = '待处理')::int       AS pending,
       count(*) FILTER (WHERE status = '处理中')::int       AS processing,
       count(*) FILTER (WHERE status = '已完结')::int       AS closed,
       count(*) FILTER (WHERE level = '严重')::int          AS severe
FROM incident
"""

INCIDENT_BY_KIND = """
SELECT kind, count(*)::int AS cnt FROM incident GROUP BY kind ORDER BY cnt DESC
"""

INCIDENT_RECENT = """
SELECT code, kind, level, status, coalesce(road_name, '未命名路段') AS road_name,
       to_char(occurred_at, 'MM-DD HH24:MI') AS occurred_at
FROM incident
ORDER BY occurred_at DESC
LIMIT $1
"""

# 近 24 小时趋势（用于折线图）
TREND = """
SELECT to_char(date_trunc('hour', ts), 'HH24:00') AS t,
       round(avg(congestion), 2)                   AS idx,
       round(avg(speed_kmh), 1)                    AS speed,
       round(avg(flow_vph))::int                   AS flow
FROM traffic_flow
GROUP BY date_trunc('hour', ts)
ORDER BY date_trunc('hour', ts)
"""

# 行政区热力（含 bbox 供前端 fitBounds）
DISTRICT_HEAT = """
SELECT d.id, d.pac, d.name, d.level,
       (SELECT round(sum(r.length_m) / 1000)::int FROM road r
         WHERE r.district_id = d.id)                                   AS road_km,
       (SELECT count(*)::int FROM incident i WHERE i.district_id = d.id) AS incidents,
       (SELECT count(*)::int FROM signal s WHERE s.district_id = d.id)   AS signals,
       (SELECT count(*)::int FROM camera c WHERE c.district_id = d.id)   AS cameras,
       (SELECT count(*)::int FROM police_unit p WHERE p.district_id = d.id) AS police,
       (SELECT round(avg(rs.congestion), 2) FROM road_status rs
          JOIN road r2 ON r2.id = rs.road_id
         WHERE r2.district_id = d.id)                                  AS avg_index,
       (SELECT round(avg(rs.speed_kmh), 1) FROM road_status rs
          JOIN road r2 ON r2.id = rs.road_id
         WHERE r2.district_id = d.id)                                  AS avg_speed,
       (SELECT sum(dv.cnt)::int FROM district_vehicle dv
         WHERE dv.district_id = d.id
           AND dv.ts = (SELECT max(ts) FROM district_vehicle))         AS vehicles,
       ST_XMin(d.geom) AS xmin, ST_YMin(d.geom) AS ymin,
       ST_XMax(d.geom) AS xmax, ST_YMax(d.geom) AS ymax
FROM district d
ORDER BY avg_index DESC NULLS LAST
"""

# 区域车辆分布（最新时刻，按车型）
VEHICLE_BY_TYPE = """
SELECT vehicle_type AS type, sum(cnt)::int AS cnt
FROM district_vehicle
WHERE ts = (SELECT max(ts) FROM district_vehicle)
GROUP BY vehicle_type
ORDER BY cnt DESC
"""

# 区域车辆分布（最新时刻，按行政区）
VEHICLE_BY_DISTRICT = """
SELECT d.name, sum(dv.cnt)::int AS cnt
FROM district_vehicle dv
JOIN district d ON d.id = dv.district_id
WHERE dv.ts = (SELECT max(ts) FROM district_vehicle)
GROUP BY d.name
ORDER BY cnt DESC
"""

# 地铁线路清单（用于线路开关）
METRO_LINES = """
SELECT line_no,
       min(colour)                              AS colour,
       count(*)::int                            AS segs,
       round(sum(length_m) / 1000)::int         AS km
FROM metro_line
WHERE coalesce(line_no, '') <> ''
GROUP BY line_no
ORDER BY nullif(regexp_replace(line_no, '\\D', '', 'g'), '')::int NULLS LAST
"""

# 公交与轨道的总体规模
TRANSIT_SUMMARY = """
SELECT (SELECT count(*)::int FROM metro_line)    AS metro_lines,
       (SELECT count(*)::int FROM metro_station) AS metro_stations,
       (SELECT count(*)::int FROM bus_route)     AS bus_routes,
       (SELECT count(*)::int FROM bus_stop)      AS bus_stops
"""

BUS_NETWORKS = """
SELECT network, count(*)::int AS routes
FROM bus_route
WHERE coalesce(network, '') <> ''
GROUP BY network
ORDER BY routes DESC
LIMIT 8
"""
