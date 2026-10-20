<script setup>
import { onBeforeUnmount, onMounted } from 'vue'
import { api } from './api'
import { applyMode, state } from './state'

import ScreenHeader from './components/ScreenHeader.vue'
import MapView from './components/MapView.vue'
import CongestionPanel from './components/panels/CongestionPanel.vue'
import DistrictHeatPanel from './components/panels/DistrictHeatPanel.vue'
import IncidentPanel from './components/panels/IncidentPanel.vue'
import ModePanel from './components/panels/ModePanel.vue'
import RealtimePanel from './components/panels/RealtimePanel.vue'
import SignalPanel from './components/panels/SignalPanel.vue'
import VehiclePanel from './components/panels/VehiclePanel.vue'

let timer = null
let retryTimer = null
let retryCount = 0
const MAX_RETRY = 10

/**
 * 拉取大屏数据。
 * 后端重启期间页面加载会失败，所以这里做自动重试 ——
 * 否则用户只会看到一句"后端服务未启动"，而实际上服务早就好了。
 */
async function loadAll() {
  try {
    const [overview, trend, districts, vehicles, incidents, metroLines, transit] = await Promise.all([
      api.overview(),
      api.trend(),
      api.districts(),
      api.vehicles(),
      api.recentIncidents(14),
      api.metroLines(),
      api.transitSummary(),
    ])
    Object.assign(state, {
      overview, trend, districts,
      vehicles, recentIncidents: incidents,
      metroLineList: metroLines,
      transit,
      metroLines: Object.keys(state.metroLines).length
        ? state.metroLines
        : Object.fromEntries(metroLines.map((l) => [l.line_no, true])),
      ready: true,
      error: '',
    })
    retryCount = 0
  } catch (e) {
    state.error = `数据加载失败：${e.message}　正在重试…（${retryCount + 1}/${MAX_RETRY}）`
    console.error('[app] 数据加载失败:', e)
    if (retryCount < MAX_RETRY) {
      retryCount += 1
      retryTimer = setTimeout(loadAll, 3000)
    } else {
      state.error = `数据加载失败：${e.message}　请确认后端服务已启动（127.0.0.1:8000），然后点此重试`
    }
  }
}

onMounted(async () => {
  timer = setInterval(() => { state.now = new Date() }, 1000)
  applyMode(state.mode)
  await loadAll()
})

onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
  if (retryTimer) clearTimeout(retryTimer)
})

/** 手动重试：重置计数立刻再拉一次 */
function retryNow() {
  if (retryTimer) clearTimeout(retryTimer)
  retryCount = 0
  loadAll()
}
</script>

<template>
  <div class="screen">
    <ScreenHeader />

    <div class="screen-body">
      <!-- 左栏：道路分级 / 交通拥堵 / 区域车辆分布 -->
      <div class="col">
        <ModePanel style="flex: 1.1" />
        <CongestionPanel style="flex: 1.15" />
        <VehiclePanel style="flex: 1" />
      </div>

      <!-- 中间：地图 -->
      <div class="map-slot">
        <MapView />
      </div>

      <!-- 右栏：交通信号 / 实时数据 / 事故处理 / 行政区热力 -->
      <div class="col">
        <SignalPanel style="flex: 0.92" />
        <RealtimePanel style="flex: 0.92" />
        <IncidentPanel style="flex: 1.12" />
        <DistrictHeatPanel style="flex: 1.06" />
      </div>
    </div>

    <div v-if="!state.ready" class="loading-mask">
      <div style="text-align: center">
        <template v-if="state.error">
          <div class="err-tip">{{ state.error }}</div>
          <button class="retry-btn" @click="retryNow">立即重试</button>
        </template>
        <template v-else>
          <div class="spin"></div>
          正在加载路网与仿真数据…
        </template>
      </div>
    </div>
  </div>
</template>
