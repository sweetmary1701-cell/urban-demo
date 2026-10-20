/**
 * GeoServer 配置
 * ===============
 * 地址用**相对路径**：由 Vite 代理转发到 localhost:8086。
 * 这样浏览器看来是同源请求，不需要在 GeoServer 端配置 CORS。
 */

export const GEOSERVER_ROOT = '/geoserver'
export const WORKSPACE = 'urban'
export const WMS_URL = `${GEOSERVER_ROOT}/${WORKSPACE}/wms`
export const WFS_URL = `${GEOSERVER_ROOT}/${WORKSPACE}/wfs`

/**
 * 图层定义
 * name  : GeoServer 中的图层名（工作区:图层）
 * style : 默认绑定的 SLD 样式名
 * query : 是否支持点击查属性（GetFeatureInfo）
 */
export const WMS_LAYERS = {
  road:          { name: `${WORKSPACE}:v_road`,        style: 'road_class',      query: true,  title: '路网' },
  district:      { name: `${WORKSPACE}:v_district`,    style: 'district_heat',   query: true,  title: '行政区' },
  signal:        { name: `${WORKSPACE}:signal`,        style: 'pt_signal',       query: true,  title: '交通信号灯' },
  camera:        { name: `${WORKSPACE}:camera`,        style: 'pt_camera',       query: true,  title: '监控/抓拍' },
  police:        { name: `${WORKSPACE}:police_unit`,   style: 'pt_police',       query: true,  title: '可调度警力' },
  incident:      { name: `${WORKSPACE}:incident`,      style: 'pt_incident',     query: true,  title: '交通事故' },
  metro_line:    { name: `${WORKSPACE}:metro_line`,    style: 'ln_metro',        query: true,  title: '地铁线路' },
  metro_station: { name: `${WORKSPACE}:metro_station`, style: 'pt_metro_station',query: true,  title: '地铁车站' },
  bus_route:     { name: `${WORKSPACE}:bus_route`,     style: 'ln_bus',          query: true,  title: '公交线路' },
  bus_stop:      { name: `${WORKSPACE}:bus_stop`,      style: 'pt_bus_stop',     query: true,  title: '公交站点' },
}

/** 路网的两种着色方式对应两个 SLD 样式 */
export const ROAD_STYLES = {
  class: 'road_class',
  congestion: 'road_congestion',
}
