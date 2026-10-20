<script setup>
import { computed } from 'vue'
import { state } from '../../state'
import MetricCard from '../MetricCard.vue'
import PanelBox from '../PanelBox.vue'

const inc = computed(() => state.overview?.incident || {})
const pol = computed(() => state.overview?.police || {})
/** 可调度警力 = 在岗 + 待命（出勤中的不可再派） */
const dispatchable = computed(() => (pol.value.on_duty ?? 0) + (pol.value.standby ?? 0))
</script>

<template>
  <PanelBox title="交通事故处理" :extra="`共 ${inc.total ?? 0} 起`">
    <div class="metric-grid c2" style="margin-bottom: 9px">
      <MetricCard label="可调度警力" :value="dispatchable" unit="组" tone="ok" />
      <MetricCard label="待处理事件" :value="inc.pending ?? '--'" unit="起" tone="danger" />
    </div>
    <div class="legend" style="margin-bottom: 8px">
      <span class="li">处理中 {{ inc.processing ?? 0 }}</span>
      <span class="li">已完结 {{ inc.closed ?? 0 }}</span>
      <span class="li">严重事件 {{ inc.severe ?? 0 }}</span>
    </div>

    <div class="incident-list">
      <div v-for="it in state.recentIncidents" :key="it.code" class="inc-row">
        <span class="tag" :class="'lv-' + it.level">{{ it.level }}</span>
        <span class="rd">{{ it.kind }} · {{ it.road_name }}</span>
        <span class="tm">{{ it.occurred_at }}</span>
      </div>
      <div v-if="!state.recentIncidents.length" class="empty-tip">暂无事件</div>
    </div>
  </PanelBox>
</template>
