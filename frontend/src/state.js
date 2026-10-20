/** 全局响应式状态（单页面大屏，用轻量 reactive 即可，不引入 Pinia） */
import { reactive } from 'vue'
import { MODE_LAYERS } from './config/layers'

export const state = reactive({
  ready: false,
  error: '',

  /** 图层模式：road 道路交通 / bus 公交运行 / metro 轨道交通 */
  mode: 'road',
  /** 道路着色依据：class 按等级 / congestion 按拥堵 */
  roadColorBy: 'class',
  /** 被高亮的道路等级（null = 不高亮，全部正常显示） */
  focusClass: null,

  /**
   * 各图层可见性。
   * 默认只点亮「路网 + 行政区」这两个底衬，业务图层全部关闭，
   * 由用户在地图的图层面板里点选开启 —— 这样演示时可以逐个讲解。
   */
  visible: {
    district: true,
    road: true,
    signal: false,
    camera: false,
    police: false,
    incident: false,
    metro_line: false,
    metro_station: false,
    bus_route: false,
    bus_stop: false,
  },
  /** 道路分级显示开关（道路等级 -> 是否显示） */
  roadClasses: {
    高速: true,
    快速路: true,
    主干道: true,
    次干道: true,
    支路: true,
  },

  /** 地铁线路开关：line_no -> 是否显示（拉取线路清单后填充） */
  metroLines: {},

  /** 后端数据 */
  overview: null,
  trend: [],
  districts: [],
  vehicles: { by_type: [], by_district: [] },
  recentIncidents: [],

  /** 交互 */
  selectedDistrict: null,
  hoverRoad: null,
  mapLoaded: false,

  /** 时钟 */
  now: new Date(),
})

/**
 * 切换模式。不再强制重置所有图层可见性（那样会把用户手动开的图层关掉），
 * 只自动点亮该模式自己的图层。
 */
export function applyMode(mode) {
  const auto = MODE_LAYERS[mode] || []
  auto.forEach((k) => { state.visible[k] = true })
}

/** 图层全开 / 全关 */
export function setAllLayers(on) {
  Object.keys(state.visible).forEach((k) => { state.visible[k] = on })
}

/**
 * 地图动作句柄。地图实例由 MapView 持有，其他面板（如行政区排行）
 * 需要触发地图动作时通过这里调用，避免把地图实例塞进全局响应式状态。
 */
export const mapApi = {
  fitDistrict: null,
  resetView: null,
}
