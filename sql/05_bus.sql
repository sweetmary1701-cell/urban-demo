-- 公交线路 + 站点
INSERT INTO bus_route (name, ref, operator, network, from_stop, to_stop, length_m, geom)
SELECT nullif(name, ''),
       nullif(ref, ''),
       nullif(operator, ''),
       nullif(network, ''),
       nullif("from", ''),
       nullif("to", ''),
       ST_Length(geom::geography),
       ST_Multi(geom)
FROM bus_route_raw;

INSERT INTO bus_stop (name, geom)
SELECT coalesce(nullif(name, ''), '未命名站'), geom
FROM bus_stop_raw;

DROP TABLE IF EXISTS bus_route_raw;
DROP TABLE IF EXISTS bus_stop_raw;
