<script setup>
import { computed } from 'vue'
import { state } from '../../state'
import MetricCard from '../MetricCard.vue'
import PanelBox from '../PanelBox.vue'

const s = computed(() => state.overview?.signal || {})
const cam = computed(() => state.overview?.camera || {})
const pol = computed(() => state.overview?.police || {})
</script>

<template>
  <PanelBox title="实时数据" extra="接入设备实时概览">
    <div class="metric-grid c2">
      <MetricCard label="交通信号在线" :value="s.ok ?? '--'" unit="路" tone="accent2" />
      <MetricCard label="视频监控" :value="cam.monitor ?? '--'" unit="路" />
      <MetricCard label="警务出勤" :value="pol.dispatched ?? '--'" unit="组" tone="warn" />
      <MetricCard label="违法抓拍" :value="cam.violation ?? '--'" unit="路" tone="danger" />
    </div>
    <div class="legend" style="margin-top: 9px">
      <span class="li">监控离线 {{ cam.offline ?? 0 }} 路</span>
      <span class="li">警力在岗 {{ pol.on_duty ?? 0 }} / 待命 {{ pol.standby ?? 0 }}</span>
      <span class="li">在编警员 {{ pol.officers ?? 0 }} 人</span>
    </div>
  </PanelBox>
</template>
