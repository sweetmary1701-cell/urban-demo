-- 路网归一化为五级分类
INSERT INTO road (osm_id, name, ref, road_class, highway, lanes, oneway,
                  bridge, tunnel, toll, length_m, geom)
SELECT id,
       nullif(name, ''),
       nullif(ref, ''),
       CASE highway
           WHEN 'motorway'     THEN '高速'
           WHEN 'trunk'        THEN '快速路'
           WHEN 'primary'      THEN '主干道'
           WHEN 'secondary'    THEN '次干道'
           WHEN 'tertiary'     THEN '支路'
           WHEN 'residential'  THEN '支路'
           WHEN 'unclassified' THEN '支路'
           ELSE '其他'
       END,
       highway,
       CASE WHEN lanes ~ '^[0-9]+$' THEN lanes::smallint END,
       CASE oneway WHEN 'yes' THEN 1 WHEN '-1' THEN -1 WHEN 'no' THEN 0 END,
       (bridge IN ('yes', 'viaduct', 'movable')),
       (tunnel = 'yes'),
       (toll = 'yes'),
       ST_Length(geom::geography),
       geom
FROM road_raw;

DROP TABLE IF EXISTS road_raw;

-- 按道路中点归属行政区（一条路只归一个区，便于按区统计/热力图）
-- 注意: road.geom 是 MultiLineString，ST_LineInterpolatePoint 不接受多部件几何，
--       因此用 ST_PointOnSurface —— 它保证返回落在几何体上的点，且支持任意类型
UPDATE road r
SET district_id = d.id
FROM district d
WHERE ST_Intersects(d.geom, ST_PointOnSurface(r.geom));
