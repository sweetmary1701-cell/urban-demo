<script setup>
import { computed } from 'vue'
import { AXIS_LABEL, AXIS_LINE, GRID, SPLIT_LINE, TOOLTIP } from '../../config/chart'
import { state } from '../../state'
import BaseChart from '../BaseChart.vue'
import MetricCard from '../MetricCard.vue'
import PanelBox from '../PanelBox.vue'

const c = computed(() => state.overview?.congestion || {})
const incident = computed(() => state.overview?.incident || {})

const option = computed(() => {
  const t = state.trend.map((x) => x.t)
  return {
    grid: { ...GRID, top: 26, bottom: 18 },
    tooltip: TOOLTIP,
    legend: {
      show: true, right: 0, top: 0, itemWidth: 10, itemHeight: 6,
      textStyle: { color: '#7fa8cc', fontSize: 10 },
      data: ['拥堵指数', '平均车速'],
    },
    xAxis: {
      type: 'category', data: t, boundaryGap: false,
      axisLabel: { ...AXIS_LABEL, interval: 3 },
      axisLine: AXIS_LINE, axisTick: { show: false },
    },
    yAxis: [
      {
        type: 'value', name: '指数', nameTextStyle: { color: '#5b7f9e', fontSize: 10 },
        min: 1, max: 3.2, axisLabel: AXIS_LABEL, axisLine: { show: false },
        splitLine: SPLIT_LINE,
      },
      {
        type: 'value', name: 'km/h', nameTextStyle: { color: '#5b7f9e', fontSize: 10 },
        axisLabel: AXIS_LABEL, axisLine: { show: false }, splitLine: { show: false },
      },
    ],
    series: [
      {
        name: '拥堵指数', type: 'line', smooth: true, symbol: 'none',
        data: state.trend.map((x) => x.idx),
        lineStyle: { width: 2, color: '#ff9c2b' },
        areaStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: 'rgba(255,156,43,0.42)' },
              { offset: 1, color: 'rgba(255,156,43,0.02)' },
            ],
          },
        },
      },
      {
        name: '平均车速', type: 'line', smooth: true, symbol: 'none', yAxisIndex: 1,
        data: state.trend.map((x) => x.speed),
        lineStyle: { width: 2, color: '#35c8ff' },
      },
    ],
  }
})
</script>

<template>
  <PanelBox title="交通拥堵" extra="全市路网实时">
    <div class="metric-grid c2" style="margin-bottom: 8px">
      <MetricCard label="拥堵处数量" :value="c.congested ?? '--'" unit="处" tone="warn" />
      <MetricCard label="平均拥堵指数" :value="c.avg_index ?? '--'" />
      <MetricCard label="平均车速" :value="c.avg_speed ?? '--'" unit="km/h" tone="accent2" />
      <MetricCard label="路网异常事件" :value="incident.total ?? '--'" unit="起" tone="danger" />
    </div>
    <BaseChart :option="option" style="min-height: 96px" />
  </PanelBox>
</template>
