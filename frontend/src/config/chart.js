/** ECharts 暗色主题公共配置 */

export const AXIS_LABEL = { color: '#7fa8cc', fontSize: 10 }
export const AXIS_LINE = { lineStyle: { color: 'rgba(90,150,200,0.28)' } }
export const SPLIT_LINE = { lineStyle: { color: 'rgba(90,150,200,0.10)' } }
export const TOOLTIP = {
  trigger: 'axis',
  backgroundColor: 'rgba(7,28,52,0.95)',
  borderColor: 'rgba(64,158,255,0.4)',
  textStyle: { color: '#d2e8ff', fontSize: 11 },
  axisPointer: { lineStyle: { color: 'rgba(64,190,255,0.5)' } },
}
export const GRID = { left: 34, right: 34, top: 24, bottom: 20 }

/** 渐变柱条 */
export function barGradient(from, to) {
  return {
    type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
    colorStops: [{ offset: 0, color: from }, { offset: 1, color: to }],
  }
}
