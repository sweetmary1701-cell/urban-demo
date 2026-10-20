/** 图层控制项定义（地图上的图层开关面板使用） */

export const LAYER_CONTROLS = [
  { key: 'road',          label: '路网',          color: '#ffd666', shape: 'line' },
  { key: 'district',      label: '行政区',        color: '#5abeff', shape: 'line' },
  { key: 'signal',        label: '交通信号灯',    color: '#12e6a0', shape: 'dot'  },
  { key: 'camera',        label: '监控 / 抓拍',   color: '#35c8ff', shape: 'dot'  },
  { key: 'police',        label: '可调度警力',    color: '#2ee6c0', shape: 'dot'  },
  { key: 'incident',      label: '交通事故',      color: '#ff8c42', shape: 'dot'  },
  { key: 'metro_line',    label: '地铁线路',      color: '#4fa8ff', shape: 'line' },
  { key: 'metro_station', label: '地铁车站',      color: '#ffffff', shape: 'dot'  },
  { key: 'bus_route',     label: '公交线路',      color: '#ffb14d', shape: 'line' },
  { key: 'bus_stop',      label: '公交站点',      color: '#ffb14d', shape: 'dot'  },
]

/** 打开某个模式时，自动点亮的图层（其余保持用户当前设置） */
export const MODE_LAYERS = {
  metro: ['metro_line', 'metro_station'],
  bus: ['bus_route', 'bus_stop'],
  road: [],
}
