<script setup>
import { computed } from 'vue'
import { mapApi, state } from '../../state'
import PanelBox from '../PanelBox.vue'

const rows = computed(() => state.districts || [])
const maxIndex = computed(() => Math.max(1, ...rows.value.map((d) => d.avg_index || 0)))

function pick(d) {
  state.selectedDistrict = d
  mapApi.fitDistrict?.(d)
}
</script>

<template>
  <PanelBox title="行政区热力图" extra="点击可缩放到该区">
    <div class="rank-list">
      <div
        v-for="(d, i) in rows"
        :key="d.pac"
        class="rank-row"
        :class="{ active: state.selectedDistrict?.pac === d.pac }"
        @click="pick(d)"
      >
        <span class="no">{{ i + 1 }}</span>
        <span class="nm">{{ d.name }}</span>
        <span class="bar-wrap">
          <i class="bar" :style="{ width: ((d.avg_index || 0) / maxIndex) * 100 + '%' }"></i>
        </span>
        <span class="num">{{ d.avg_index ?? '--' }}</span>
        <span class="num sub" :title="`事件 ${d.incidents} 起 / 路网 ${d.road_km} km`">
          {{ d.incidents }}起
        </span>
      </div>
      <div v-if="!rows.length" class="empty-tip">暂无数据</div>
    </div>
  </PanelBox>
</template>
