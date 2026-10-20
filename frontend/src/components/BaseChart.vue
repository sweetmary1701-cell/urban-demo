<script setup>
import * as echarts from 'echarts'
import { onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'

const props = defineProps({ option: { type: Object, default: null } })
const el = ref(null)
const chart = shallowRef(null)   // ECharts 实例不能放进 reactive
let ro = null

onMounted(() => {
  chart.value = echarts.init(el.value, null, { renderer: 'canvas' })
  if (props.option) chart.value.setOption(props.option)
  ro = new ResizeObserver(() => chart.value?.resize())
  ro.observe(el.value)
})

watch(
  () => props.option,
  (o) => { if (o && chart.value) chart.value.setOption(o, true) },
  { deep: true },
)

onBeforeUnmount(() => {
  ro?.disconnect()
  chart.value?.dispose()
})
</script>

<template>
  <div ref="el" class="chart"></div>
</template>
