-- ============================================================
--  智慧交通可视化大屏 · 数据库结构
--  数据库 : urban_demo
--  坐标系 : EPSG:4326 (WGS84) —— 全项目统一，避免多 SRID 空间连接
--  说明   : 基础地理来自 OSM / H51.gdb，业务数据由 Python 仿真生成
-- ============================================================

CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================
--  1. 基础地理
-- ============================================================

-- 行政区（行政区热力图 / 区域车辆分布 的统计单元）
DROP TABLE IF EXISTS district CASCADE;
CREATE TABLE district (
    id        serial PRIMARY KEY,
    pac       varchar(12) UNIQUE,                 -- 行政区划代码，如 320508
    name      varchar(64) NOT NULL,
    level     varchar(16),                        -- 区 / 县级市
    area_km2  numeric(12,2),
    geom      geometry(MultiPolygon, 4326) NOT NULL
);
CREATE INDEX district_geom_gix ON district USING GIST (geom);

-- 路网（统一五级分类：高速 / 快速路 / 主干道 / 次干道 / 支路）
DROP TABLE IF EXISTS road CASCADE;
CREATE TABLE road (
    id         bigserial PRIMARY KEY,
    osm_id     text,
    name       varchar(200),
    ref        varchar(64),                       -- 道路编号 G2 / S48 / X205
    road_class varchar(16),                       -- 归一化等级（前端按此渲染）
    highway    varchar(24),                       -- 原始 OSM 分级
    lanes      smallint,
    oneway     smallint,                          -- 1 单向 / 0 双向 / -1 反向单行
    bridge     boolean,
    tunnel     boolean,
    toll       boolean,
    length_m   double precision,
    district_id integer REFERENCES district(id),  -- 归属行政区（按中点判定）
    geom       geometry(MultiLineString, 4326) NOT NULL
);
CREATE INDEX road_geom_gix  ON road USING GIST (geom);
CREATE INDEX road_class_idx ON road (road_class);
CREATE INDEX road_dist_idx  ON road (district_id);

-- 地铁线路
DROP TABLE IF EXISTS metro_line CASCADE;
CREATE TABLE metro_line (
    id       serial PRIMARY KEY,
    name     varchar(64),
    line_no  varchar(16),
    colour   varchar(16),                         -- 线路官方配色
    length_m double precision,
    geom     geometry(MultiLineString, 4326) NOT NULL
);
CREATE INDEX metro_line_geom_gix ON metro_line USING GIST (geom);

-- 地铁车站
DROP TABLE IF EXISTS metro_station CASCADE;
CREATE TABLE metro_station (
    id   serial PRIMARY KEY,
    name varchar(100),
    geom geometry(Point, 4326) NOT NULL
);
CREATE INDEX metro_station_geom_gix ON metro_station USING GIST (geom);

-- 公交线路
DROP TABLE IF EXISTS bus_route CASCADE;
CREATE TABLE bus_route (
    id        serial PRIMARY KEY,
    name      varchar(200),
    ref       varchar(64),                        -- 线路号
    operator  varchar(120),
    network   varchar(80),
    from_stop varchar(120),
    to_stop   varchar(120),
    length_m  double precision,
    geom      geometry(MultiLineString, 4326) NOT NULL
);
CREATE INDEX bus_route_geom_gix ON bus_route USING GIST (geom);

-- 公交站点
DROP TABLE IF EXISTS bus_stop CASCADE;
CREATE TABLE bus_stop (
    id   serial PRIMARY KEY,
    name varchar(120),
    geom geometry(Point, 4326) NOT NULL
);
CREATE INDEX bus_stop_geom_gix ON bus_stop USING GIST (geom);

-- ============================================================
--  2. 交通管理（业务仿真数据）
-- ============================================================

-- 交通信号灯
DROP TABLE IF EXISTS signal CASCADE;
CREATE TABLE signal (
    id          serial PRIMARY KEY,
    code        varchar(32) UNIQUE,
    name        varchar(120),
    district_id integer REFERENCES district(id),
    road_id     bigint  REFERENCES road(id) ON DELETE SET NULL,
    status      varchar(16) NOT NULL,             -- 正常 / 故障 / 警告
    cycle_sec   smallint,                         -- 配时周期（秒）
    updated_at  timestamptz NOT NULL DEFAULT now(),
    geom        geometry(Point, 4326) NOT NULL
);
CREATE INDEX signal_geom_gix   ON signal USING GIST (geom);
CREATE INDEX signal_status_idx ON signal (status);
CREATE INDEX signal_dist_idx   ON signal (district_id);

-- 视频监控 / 违法抓拍
DROP TABLE IF EXISTS camera CASCADE;
CREATE TABLE camera (
    id          serial PRIMARY KEY,
    code        varchar(32) UNIQUE,
    name        varchar(120),
    kind        varchar(16) NOT NULL,             -- 视频监控 / 违法抓拍
    district_id integer REFERENCES district(id),
    road_id     bigint  REFERENCES road(id) ON DELETE SET NULL,
    status      varchar(16) NOT NULL,             -- 在线 / 离线
    geom        geometry(Point, 4326) NOT NULL
);
CREATE INDEX camera_geom_gix ON camera USING GIST (geom);
CREATE INDEX camera_kind_idx ON camera (kind);

-- 警力（可调度资源）
DROP TABLE IF EXISTS police_unit CASCADE;
CREATE TABLE police_unit (
    id          serial PRIMARY KEY,
    code        varchar(32) UNIQUE,
    name        varchar(120),
    kind        varchar(24),                      -- 交警大队 / 中队 / 铁骑 / 巡逻车
    district_id integer REFERENCES district(id),
    status      varchar(16) NOT NULL,             -- 在岗 / 出勤 / 待命
    officer_cnt smallint,
    geom        geometry(Point, 4326) NOT NULL
);
CREATE INDEX police_geom_gix ON police_unit USING GIST (geom);
CREATE INDEX police_status_idx ON police_unit (status);

-- 事件 / 事故（待处理事件）
DROP TABLE IF EXISTS incident CASCADE;
CREATE TABLE incident (
    id          bigserial PRIMARY KEY,
    code        varchar(32) UNIQUE,
    kind        varchar(24) NOT NULL,             -- 交通事故/车辆故障/道路施工/积水/异常拥堵
    level       varchar(16) NOT NULL,             -- 一般 / 较重 / 严重
    status      varchar(16) NOT NULL,             -- 待处理 / 处理中 / 已完结
    district_id integer REFERENCES district(id),
    road_id     bigint  REFERENCES road(id) ON DELETE SET NULL,
    road_name   varchar(200),
    police_id   integer REFERENCES police_unit(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL,
    closed_at   timestamptz,
    geom        geometry(Point, 4326) NOT NULL
);
CREATE INDEX incident_geom_gix   ON incident USING GIST (geom);
CREATE INDEX incident_status_idx ON incident (status);
CREATE INDEX incident_dist_idx   ON incident (district_id);

-- 路段实时状态（拥堵指数 / 平均车速，用于地图染色）
DROP TABLE IF EXISTS road_status CASCADE;
CREATE TABLE road_status (
    road_id    bigint PRIMARY KEY REFERENCES road(id) ON DELETE CASCADE,
    speed_kmh  numeric(5,1) NOT NULL,             -- 平均车速
    free_speed numeric(5,1) NOT NULL,             -- 自由流速度
    congestion numeric(4,2) NOT NULL,             -- 拥堵指数 1.00 ~ 5.00
    level      varchar(16) NOT NULL,              -- 畅通/基本畅通/轻度拥堵/中度拥堵/严重拥堵
    flow_vph   integer,                           -- 当前小时流量
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX road_status_level_idx ON road_status (level);

-- 时序流量（趋势图 / 时间轴回放）
DROP TABLE IF EXISTS traffic_flow CASCADE;
CREATE TABLE traffic_flow (
    id         bigserial PRIMARY KEY,
    road_id    bigint NOT NULL REFERENCES road(id) ON DELETE CASCADE,
    ts         timestamptz NOT NULL,
    flow_vph   integer,
    speed_kmh  numeric(5,1),
    congestion numeric(4,2)
);
CREATE INDEX traffic_flow_ts_idx   ON traffic_flow (ts);
CREATE INDEX traffic_flow_road_idx ON traffic_flow (road_id, ts);

-- 区域车辆分布（按行政区）
DROP TABLE IF EXISTS district_vehicle CASCADE;
CREATE TABLE district_vehicle (
    id           bigserial PRIMARY KEY,
    district_id  integer NOT NULL REFERENCES district(id) ON DELETE CASCADE,
    ts           timestamptz NOT NULL,
    vehicle_type varchar(24) NOT NULL,            -- 小汽车/货车/公交车/出租车/网约车
    cnt          integer NOT NULL
);
CREATE INDEX district_vehicle_idx ON district_vehicle (ts, district_id);
