-- 地铁线路 + 车站
INSERT INTO metro_line (name, line_no, colour, length_m, geom)
SELECT left(split_part(name, '：', 1), 16),
       -- 线路号统一成「N号线」：原始 name 有 "1号线：钟南街 → 木渎"、
       -- "苏州轨道交通7号线 常楼→木里" 等多种写法，必须归一化才能做线路筛选
       coalesce(substring(name from '([0-9]+号线)'), left(split_part(name, '：', 1), 16)),
       nullif(colour, ''),
       ST_Length(geom::geography),
       ST_Multi(geom)
FROM metro_raw;

INSERT INTO metro_station (name, geom)
SELECT coalesce(nullif(name, ''), '未命名站'), geom
FROM metro_station_raw;

DROP TABLE IF EXISTS metro_raw;
DROP TABLE IF EXISTS metro_station_raw;
