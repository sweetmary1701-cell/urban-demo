<script setup>
import { computed } from 'vue'
import { state } from '../../state'
import MetricCard from '../MetricCard.vue'
import PanelBox from '../PanelBox.vue'

const s = computed(() => state.overview?.signal || {})
const rate = computed(() => {
  if (!s.value.total) return { ok: 0, warn: 0, fault: 0 }
  return {
    ok: (s.value.ok / s.value.total) * 100,
    warn: (s.value.warn / s.value.total) * 100,
    fault: (s.value.fault / s.value.total) * 100,
  }
})
</script>

<template>
  <PanelBox title="交通信号" extra="全市信号灯运行状态">
    <div class="metric-grid c2" style="margin-bottom: 9px">
      <MetricCard label="信号灯总数" :value="s.total ?? '--'" unit="个" />
      <MetricCard label="在线正常" :value="s.ok ?? '--'" unit="个" tone="ok" />
      <MetricCard label="故障数量" :value="s.fault ?? '--'" unit="个" tone="danger" />
      <MetricCard label="异常警告" :value="s.warn ?? '--'" unit="个" tone="warn" />
    </div>

    <!-- 运行状态占比条 -->
    <div style="display: flex; height: 7px; border-radius: 4px; overflow: hidden; background: rgba(255,255,255,.06)">
      <div :style="{ width: rate.ok + '%', background: '#12e6a0' }"></div>
      <div :style="{ width: rate.warn + '%', background: '#ffc53d' }"></div>
      <div :style="{ width: rate.fault + '%', background: '#ff5c5c' }"></div>
    </div>
    <div class="legend" style="margin-top: 7px">
      <span class="li"><i class="dot" style="background: #12e6a0"></i>正常 {{ rate.ok.toFixed(1) }}%</span>
      <span class="li"><i class="dot" style="background: #ffc53d"></i>警告 {{ rate.warn.toFixed(1) }}%</span>
      <span class="li"><i class="dot" style="background: #ff5c5c"></i>故障 {{ rate.fault.toFixed(1) }}%</span>
    </div>
  </PanelBox>
</template>
