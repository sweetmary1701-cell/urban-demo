<script setup>
import { computed, onMounted, ref } from 'vue'
import { CONGESTION_LEVELS, ROAD_CLASSES } from '../config/map'
import { useMapEngine } from '../composables/useMapEngine'
import { mapApi, state } from '../state'
import LayerControl from './LayerControl.vue'

const mapEl = ref(null)
const engine = useMapEngine()

onMounted(() => {
  engine.init(mapEl.value)
  // 供其他面板触发地图动作
  mapApi.fitDistrict = engine.fitDistrict
  mapApi.resetView = engine.resetView
})

const isRoadMode = computed(() => state.mode === 'road')

/** 交通事故图层快捷开关 */
function toggleIncident() {
  state.visible.incident = !state.visible.incident
}

/** 图例内容随模式和着色方式变化 */
const legendItems = computed(() => {
  if (isRoadMode.value) {
    if (state.roadColorBy === 'congestion') {
      return CONGESTION_LEVELS.map((c) => ({ label: c.key, color: c.color, line: true }))
    }
    return ROAD_CLASSES.filter((c) => state.roadClasses[c.key]).map((c) => ({
      label: c.key, color: c.color, line: true,
    }))
  }
  if (state.mode === 'metro') {
    return [
      { label: '地铁线路', color: '#4fa8ff', line: true },
      { label: '地铁车站', color: '#ffffff', dot: true },
    ]
  }
  return [
    { label: '公交线路', color: '#ffb14d', line: true },
    { label: '公交站点', color: '#ffb14d', dot: true },
  ]
})

const roadKm = computed(() => {
  const list = state.overview?.road_classes || []
  return list.reduce((s, x) => s + (x.km || 0), 0)
})

</script>

<template>
  <div class="map-wrap">
    <div ref="mapEl" class="map-canvas"></div>

    <!-- 左上：图层控制 -->
    <div class="map-overlay-tl">
      <LayerControl />
    </div>

    <!-- 左下：图例 -->
    <div class="map-overlay-bl" style="bottom: 42px">
      <div class="map-legend">
        <div class="lt">
          {{ isRoadMode ? (state.roadColorBy === 'congestion' ? '拥堵状态' : '道路分级') : '线网图例' }}
        </div>
        <div v-for="it in legendItems" :key="it.label" class="ll">
          <span
            class="sw"
            :style="{
              background: it.color,
              width: it.dot ? '8px' : '16px',
              height: it.dot ? '8px' : '3px',
              borderRadius: it.dot ? '50%' : '2px',
            }"
          ></span>
          {{ it.label }}
        </div>
      </div>
    </div>

    <!-- 右上角：统计 + 快捷按钮 -->
    <div class="map-overlay-tr">
      <div class="map-stats" style="margin-bottom: 8px">
        <div class="map-stat">
          <div class="v">{{ roadKm.toLocaleString() }}</div>
          <div class="k">路网里程 km</div>
        </div>
        <div class="map-stat">
          <div class="v">{{ state.overview?.congestion?.congested ?? '--' }}</div>
          <div class="k">拥堵路段</div>
        </div>
        <div class="map-stat">
          <div class="v">{{ state.overview?.congestion?.avg_speed ?? '--' }}</div>
          <div class="k">平均车速 km/h</div>
        </div>
      </div>
      <div class="basemap-switch" style="justify-content: flex-end">
        <button
          :class="{ active: state.visible.incident }"
          class="incident-btn"
          @click="toggleIncident"
        >
          交通事故图层{{ state.visible.incident ? ' · 开' : ' · 关' }}
        </button>
        <button v-if="state.focusClass" @click="state.focusClass = null">
          显示全部等级
        </button>
        <button @click="engine.resetView()">视图复位</button>
      </div>
    </div>

    <div v-if="!state.mapLoaded" class="loading-mask" style="background: rgba(3,10,22,0.55)">
      <div style="text-align: center">
        <div class="spin"></div>
        <template v-if="state.error">
          <div class="err-tip">{{ state.error }}</div>
        </template>
        <template v-else>地图加载中…</template>
      </div>
    </div>
  </div>
</template>
