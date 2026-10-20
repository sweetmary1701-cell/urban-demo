-- 入库结果汇总
SELECT 'district'      AS tbl, count(*)::text AS cnt FROM district
UNION ALL SELECT 'road',          count(*)::text FROM road
UNION ALL SELECT 'road(高速)',    count(*)::text FROM road WHERE road_class = '高速'
UNION ALL SELECT 'metro_line',    count(*)::text FROM metro_line
UNION ALL SELECT 'metro_station', count(*)::text FROM metro_station
UNION ALL SELECT 'bus_route',     count(*)::text FROM bus_route
UNION ALL SELECT 'bus_stop',      count(*)::text FROM bus_stop;
