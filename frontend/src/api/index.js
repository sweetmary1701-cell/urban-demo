/**
 * 业务接口封装
 * =============
 * 只管 FastAPI 提供的统计接口（指标卡、图表、排行）。
 * 地理数据的获取由 GeoServer 的 WMS 服务承担，见 config/geoserver.js。
 */

const BASE = '/api'

async function getJson(path) {
  const res = await fetch(BASE + path)
  if (!res.ok) throw new Error(`${path} -> HTTP ${res.status}`)
  return res.json()
}

export const api = {
  overview: () => getJson('/overview'),
  trend: () => getJson('/trend'),
  districts: () => getJson('/districts'),
  vehicles: () => getJson('/vehicles'),
  recentIncidents: (limit = 12) => getJson(`/incidents/recent?limit=${limit}`),
  metroLines: () => getJson('/metro/lines'),
  transitSummary: () => getJson('/transit/summary'),
  health: () => getJson('/health'),
}
