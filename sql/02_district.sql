-- 行政区：按 PAC 融合多部件并计算面积
INSERT INTO district (pac, name, level, area_km2, geom)
SELECT PAC::text,
       min(NAME),
       CASE WHEN PAC::text LIKE '32058%' THEN '县级市' ELSE '区' END,
       round((ST_Area(ST_Union(geom)::geography) / 1000000)::numeric, 2),
       ST_Multi(ST_Union(geom))
FROM district_raw
GROUP BY PAC;

DROP TABLE IF EXISTS district_raw;
