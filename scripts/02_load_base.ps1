# ============================================================
#  基础地理数据入库
#  用法:  pwsh -File "scripts\02_load_base.ps1"
#  入库内容: 行政区 / 路网(五级分类) / 地铁线路+车站 / 公交线路+站点
#  数据源:   suzhouH51\H51.gdb (CGCS2000) + GeoJSON\*.geojson (WGS84)
# ============================================================
$ErrorActionPreference = 'Stop'

$env:PGCLIENTENCODING = 'UTF8'
$env:PGPASSWORD       = 'postgres'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Ws         = Split-Path -Parent $PSScriptRoot
$PsqlExe    = 'E:\Program Files\PostgreSQL\18\bin\psql.exe'
$Ogr2OgrExe = 'E:\Program Files\QGIS\bin\ogr2ogr.exe'
$Db         = 'urban_demo'
$Conn       = 'PG:host=localhost port=5432 dbname=urban_demo user=postgres password=postgres'

# 执行内联 SQL —— 只能放 ASCII，带中文的语句一律走 SQL 文件
function Invoke-Sql {
    param([Parameter(Mandatory)][string]$Sql)
    & $PsqlExe -U postgres -h localhost -p 5432 -d $Db -w -v ON_ERROR_STOP=1 -q -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "SQL 失败 (exit $LASTEXITCODE): $Sql" }
}

# 执行 SQL 文件（UTF-8 安全，可含中文）
function Invoke-SqlFile {
    param([Parameter(Mandatory)][string]$File)
    & $PsqlExe -U postgres -h localhost -p 5432 -d $Db -w -v ON_ERROR_STOP=1 -q -f $File
    if ($LASTEXITCODE -ne 0) { throw "SQL 文件失败 (exit $LASTEXITCODE): $File" }
}

function Invoke-Ogr {
    param([Parameter(Mandatory)][string[]]$ArgList)
    & $Ogr2OgrExe @ArgList
    if ($LASTEXITCODE -ne 0) { throw "ogr2ogr 失败 (exit $LASTEXITCODE): $($ArgList -join ' ')" }
}

function Step { param([string]$No, [string]$Msg) Write-Host "`n===== $No. $Msg =====" -ForegroundColor Cyan }

$sw = [Diagnostics.Stopwatch]::StartNew()

# ------------------------------------------------------------
Step '1' '建表'
Invoke-Sql -Sql "DROP TABLE IF EXISTS road_raw, district_raw, metro_raw, metro_station_raw, bus_route_raw, bus_stop_raw, t_test, t_test2 CASCADE;"
Invoke-SqlFile -File (Join-Path $Ws 'sql\01_schema.sql')
Write-Host '  表结构已创建'

# ------------------------------------------------------------
Step '2' '行政区（H51.gdb → BOUA，苏州范围，CGCS2000 → WGS84）'
Invoke-Ogr @(
    '-f', 'PostgreSQL', $Conn,
    (Join-Path $Ws 'suzhouH51\H51.gdb'), 'BOUA',
    '-nln', 'district_raw', '-lco', 'GEOMETRY_NAME=geom',
    '-nlt', 'PROMOTE_TO_MULTI',
    '-s_srs', 'EPSG:4490', '-t_srs', 'EPSG:4326',
    '-where', 'PAC >= 320500 AND PAC < 320600'
)
Invoke-SqlFile -File (Join-Path $Ws 'sql\02_district.sql')
& $PsqlExe -U postgres -h localhost -p 5432 -d $Db -w -c 'SELECT pac, name, level, area_km2 FROM district ORDER BY pac;'

# ------------------------------------------------------------
Step '3' '路网（urban roads.geojson，67153 条）'
Invoke-Ogr @(
    '-f', 'PostgreSQL', $Conn,
    (Join-Path $Ws 'GeoJSON\urban roads.geojson'),
    '-nln', 'road_raw', '-lco', 'GEOMETRY_NAME=geom',
    '-nlt', 'PROMOTE_TO_MULTI',
    '-select', 'id,name,ref,highway,lanes,oneway,bridge,tunnel,toll'
)
Write-Host ("  ogr2ogr 完成，累计 {0:N0}s" -f $sw.Elapsed.TotalSeconds)

Step '4' '归一化为五级分类 + 归属行政区'
Invoke-SqlFile -File (Join-Path $Ws 'sql\03_road.sql')
& $PsqlExe -U postgres -h localhost -p 5432 -d $Db -w -c "SELECT road_class, count(*) AS cnt, round(sum(length_m)/1000) AS km FROM road GROUP BY road_class ORDER BY cnt DESC;"
& $PsqlExe -U postgres -h localhost -p 5432 -d $Db -w -c 'SELECT count(*) FILTER (WHERE district_id IS NOT NULL) AS assigned, count(*) AS total FROM road;'

# ------------------------------------------------------------
Step '5' '地铁线路 + 车站'
Invoke-Ogr @(
    '-f', 'PostgreSQL', $Conn,
    (Join-Path $Ws 'GeoJSON\railway.geojson'),
    '-nln', 'metro_raw', '-lco', 'GEOMETRY_NAME=geom',
    '-nlt', 'MULTILINESTRING', '-where', "route='subway'"
)
Invoke-Ogr @(
    '-f', 'PostgreSQL', $Conn,
    (Join-Path $Ws 'GeoJSON\railway.geojson'),
    '-nln', 'metro_station_raw', '-lco', 'GEOMETRY_NAME=geom',
    '-nlt', 'POINT', '-where', 'route IS NULL'
)
Invoke-SqlFile -File (Join-Path $Ws 'sql\04_metro.sql')
& $PsqlExe -U postgres -h localhost -p 5432 -d $Db -w -c 'SELECT (SELECT count(*) FROM metro_line) AS lines, (SELECT count(*) FROM metro_station) AS stations;'

# ------------------------------------------------------------
Step '6' '公交线路 + 站点'
Invoke-Ogr @(
    '-f', 'PostgreSQL', $Conn,
    (Join-Path $Ws 'GeoJSON\Bus Routes.geojson'),
    '-nln', 'bus_route_raw', '-lco', 'GEOMETRY_NAME=geom',
    '-nlt', 'MULTILINESTRING', '-where', "route='bus'"
)
Invoke-Ogr @(
    '-f', 'PostgreSQL', $Conn,
    (Join-Path $Ws 'GeoJSON\Bus Routes.geojson'),
    '-nln', 'bus_stop_raw', '-lco', 'GEOMETRY_NAME=geom',
    '-nlt', 'POINT', '-where', 'route IS NULL'
)
Invoke-SqlFile -File (Join-Path $Ws 'sql\05_bus.sql')
& $PsqlExe -U postgres -h localhost -p 5432 -d $Db -w -c 'SELECT (SELECT count(*) FROM bus_route) AS routes, (SELECT count(*) FROM bus_stop) AS stops;'

# ------------------------------------------------------------
Step '7' '汇总'
Invoke-SqlFile -File (Join-Path $Ws 'sql\09_summary.sql')
Write-Host ("`n全部完成，总用时 {0:N0}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
