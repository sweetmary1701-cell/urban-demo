/**
 * 地图配置：天地图底图 + 配色方案
 */

// 天地图 API Key（在 console.tianditu.gov.cn 申请）
export const TIANDITU_KEY = 'a1a89977d54c1541aac6624251f762fc'

const SUBDOMAINS = [0, 1, 2, 3, 4, 5, 6, 7]

/**
 * 天地图 WMTS 瓦片地址（供 OpenLayers 的 XYZ 源使用）。
 * OL 的 XYZ 模板只认 {x}/{y}/{z}，所以这里直接把占位符写在对应参数上。
 * layer: img 影像底图 / cia 影像注记 / vec 矢量底图 / cva 矢量注记
 * 后缀 _w 表示 Web 墨卡托（EPSG:3857），与 OL 默认投影一致。
 */
export function tiandituTileUrl(layer, subdomain = 0) {
  return (
    `https://t${subdomain}.tianditu.gov.cn/${layer}_w/wmts` +
    `?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0` +
    `&LAYER=${layer}&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles` +
    `&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=${TIANDITU_KEY}`
  )
}

export const TIANDITU_SUBDOMAINS = SUBDOMAINS

/** 道路五级分类配色（需求：高速公路 / 城市快速路 / 主干道 / 次干道 / 支路） */
export const ROAD_CLASSES = [
  { key: '高速', color: '#ff4d4f', width: 4.2, order: 1, always: true },
  { key: '快速路', color: '#ff9c2b', width: 3.6, order: 2, always: true },
  { key: '主干道', color: '#ffd666', width: 2.8, order: 3, always: false },
  { key: '次干道', color: '#4facfe', width: 2.0, order: 4, always: false },
  { key: '支路', color: '#6c86a6', width: 1.1, order: 5, always: false },
]

export const ROAD_CLASS_COLOR = Object.fromEntries(ROAD_CLASSES.map((c) => [c.key, c.color]))
export const ROAD_CLASS_WIDTH = Object.fromEntries(ROAD_CLASSES.map((c) => [c.key, c.width]))

/** 拥堵等级配色 */
export const CONGESTION_LEVELS = [
  { key: '畅通', color: '#12e6a0' },
  { key: '基本畅通', color: '#8ddb3c' },
  { key: '轻度拥堵', color: '#ffd166' },
  { key: '中度拥堵', color: '#ff8c42' },
  { key: '严重拥堵', color: '#ff3b3b' },
]

export const CONGESTION_COLOR = Object.fromEntries(CONGESTION_LEVELS.map((c) => [c.key, c.color]))

/** 其他要素配色 */
export const SYMBOL_COLOR = {
  signalOk: '#12e6a0',
  signalWarn: '#ffc53d',
  signalFault: '#ff3b3b',
  cameraMonitor: '#35c8ff',
  cameraViolation: '#c17bff',
  police: '#2ee6c0',
  incident一般: '#ffd166',
  incident较重: '#ff8c42',
  incident严重: '#ff3b3b',
  metro: '#4fa8ff',
  bus: '#ffb14d',
}

/** 苏州默认视图 */
export const DEFAULT_VIEW = {
  center: [120.62, 31.32],
  zoom: 9.6,
  minZoom: 7,
  maxZoom: 18,
}
