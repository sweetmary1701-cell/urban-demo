<script setup>
import { computed } from 'vue'
import { AXIS_LABEL, GRID, TOOLTIP, barGradient } from '../../config/chart'
import { state } from '../../state'
import BaseChart from '../BaseChart.vue'
import PanelBox from '../PanelBox.vue'

const byDistrict = computed(() => state.vehicles?.by_district || [])
const total = computed(() => byDistrict.value.reduce((s, x) => s + x.cnt, 0))

const option = computed(() => {
  const rows = [...byDistrict.value].reverse()
  return {
    grid: { ...GRID, left: 62, right: 46, top: 8, bottom: 6 },
    tooltip: { ...TOOLTIP, trigger: 'item' },
    xAxis: { type: 'value', show: false },
    yAxis: {
      type: 'category',
      data: rows.map((x) => x.name),
      axisLabel: { ...AXIS_LABEL, fontSize: 11 },
      axisLine: { show: false },
      axisTick: { show: false },
    },
    series: [
      {
        type: 'bar',
        data: rows.map((x) => x.cnt),
        barWidth: 9,
        itemStyle: { borderRadius: [0, 4, 4, 0], color: barGradient('#35c8ff', '#1b7fd0') },
        label: {
          show: true, position: 'right',
          color: '#9fd4f5', fontSize: 10, formatter: '{c}',
        },
      },
    ],
  }
})
</script>

<template>
  <PanelBox title="区域车辆分布" :extra="`在途 ${total.toLocaleString()} 辆`">
    <BaseChart :option="option" style="min-height: 110px" />
  </PanelBox>
</template>
