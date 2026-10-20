-- ============================================================
--  GeoServer 专用视图
-- ============================================================
--  为什么需要这两个视图：
--  GeoServer 可以直接发布**表**，但不能发布 JOIN 查询。而路网需要
--  关联拥堵状态、行政区需要聚合统计指标，所以先在库里把结果做成视图，
--  再让 GeoServer 去发布视图。
--
--  另一个作用：视图里额外生成了 **ASCII 分类码**字段
--  （road_class_code / congestion_code / heat_code）。
--  这样 SLD 样式文件与前端 CQL 过滤条件里都不用写中文，
--  从根上避开中文编码问题。
--
--  执行顺序：必须在 01~05 各脚本之后执行。
--  幂等：可重复执行，每次都会重建视图。
-- ============================================================

-- ------------------------------------------------------------
--  v_road：路网 + 拥堵状态
--  对应 GeoServer 图层：urban:v_road
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_road CASCADE;
CREATE VIEW v_road AS
SELECT
    r.id,
    r.name,
    r.ref,
    r.road_class,                       -- 中文等级：高速 / 快速路 / 主干道 / 次干道 / 支路
    r.highway,
    r.lanes,
    r.oneway,
    r.bridge,
    r.tunnel,
    r.toll,
    r.length_m,
    r.district_id,

    -- ASCII 等级码，供 SLD 过滤与前端 CQL 使用
    CASE r.road_class
        WHEN '高速'   THEN 'hw'
        WHEN '快速路' THEN 'exp'
        WHEN '主干道' THEN 'art'
        WHEN '次干道' THEN 'sec'
        ELSE 'brn'
    END AS road_class_code,

    -- 拥堵状态（来自 road_status 表）
    s.congestion::float8  AS congestion,        -- 拥堵指数 1.0~5.0
    s.speed_kmh::float8   AS speed_kmh,         -- 平均车速
    s.level               AS congestion_level,  -- 中文等级
    CASE s.level
        WHEN '畅通'     THEN 'smooth'
        WHEN '基本畅通' THEN 'ok'
        WHEN '轻度拥堵' THEN 'slight'
        WHEN '中度拥堵' THEN 'mod'
        WHEN '严重拥堵' THEN 'severe'
        ELSE 'unknown'
    END AS congestion_code,

    -- 显式声明几何类型与 SRID，便于 GeoServer 识别
    r.geom::geometry(MultiLineString, 4326) AS geom
FROM road r
LEFT JOIN road_status s ON s.road_id = r.id;

COMMENT ON VIEW v_road IS 'GeoServer 图层 v_road：路网 + 拥堵状态 + ASCII 分类码';


-- ------------------------------------------------------------
--  v_district：行政区 + 聚合指标
--  对应 GeoServer 图层：urban:v_district
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_district CASCADE;
CREATE VIEW v_district AS
SELECT
    d.id,
    d.pac,
    d.name,
    d.level,
    d.area_km2::float8 AS area_km2,

    -- 聚合指标（子查询而非 JOIN，避免多表连接导致的行数膨胀）
    (SELECT round(sum(r.length_m) / 1000)::int
       FROM road r WHERE r.district_id = d.id)          AS road_km,
    (SELECT count(*)::int
       FROM incident i WHERE i.district_id = d.id)      AS incident_cnt,
    (SELECT count(*)::int
       FROM signal s WHERE s.district_id = d.id)        AS signal_cnt,
    (SELECT count(*)::int
       FROM camera c WHERE c.district_id = d.id)        AS camera_cnt,
    (SELECT round(avg(rs.congestion), 2)::float8
       FROM road_status rs
       JOIN road r2 ON r2.id = rs.road_id
      WHERE r2.district_id = d.id)                      AS avg_index,

    -- 热力分级码（按平均拥堵指数分四档），供 SLD 着色
    CASE
        WHEN (SELECT avg(rs.congestion) FROM road_status rs
                JOIN road r2 ON r2.id = rs.road_id
               WHERE r2.district_id = d.id) < 1.5 THEN 'lv1'
        WHEN (SELECT avg(rs.congestion) FROM road_status rs
                JOIN road r2 ON r2.id = rs.road_id
               WHERE r2.district_id = d.id) < 1.7 THEN 'lv2'
        WHEN (SELECT avg(rs.congestion) FROM road_status rs
                JOIN road r2 ON r2.id = rs.road_id
               WHERE r2.district_id = d.id) < 1.9 THEN 'lv3'
        ELSE 'lv4'
    END AS heat_code,

    d.geom::geometry(MultiPolygon, 4326) AS geom
FROM district d;

COMMENT ON VIEW v_district IS 'GeoServer 图层 v_district：行政区 + 聚合指标 + 热力分级码';


-- ============================================================
--  自检
-- ============================================================
-- SELECT count(*) FROM v_road;       -- 期望 67153
-- SELECT count(*) FROM v_district;   -- 期望 9
-- SELECT road_class_code, count(*) FROM v_road GROUP BY 1 ORDER BY 2 DESC;
