<script setup>
import { computed } from 'vue'
import { ROAD_CLASSES } from '../../config/map'
import { state } from '../../state'
import PanelBox from '../PanelBox.vue'

/* ---------------- 道路模式 ---------------- */
const roadRows = computed(() => {
  const list = state.overview?.road_classes || []
  return ROAD_CLASSES.map((c) => {
    const hit = list.find((x) => x.class === c.key)
    return { ...c, km: hit?.km ?? 0, count: hit?.count ?? 0 }
  })
})
const totalKm = computed(() => roadRows.value.reduce((s, r) => s + r.km, 0))
const totalCount = computed(() => roadRows.value.reduce((s, r) => s + r.count, 0))

function focus(key) {
  // 点某一等级 = 在地图上高亮它（其余压暗），再点一次恢复
  state.focusClass = state.focusClass === key ? null : key
}

/* ---------------- 轨道模式 ---------------- */
const lines = computed(() => state.metroLineList || [])
const onLines = computed(() => lines.value.filter((l) => state.metroLines[l.line_no]).length)

function toggleLine(no) {
  state.metroLines[no] = !state.metroLines[no]
}
function allLines(on) {
  lines.value.forEach((l) => { state.metroLines[l.line_no] = on })
}

/* ---------------- 公交模式 ---------------- */
const transit = computed(() => state.transit?.totals || {})
const busNetworks = computed(() => state.transit?.bus_networks || [])
</script>

<template>
  <!-- 道路交通管理 -->
  <PanelBox
    v-if="state.mode === 'road'"
    title="道路分级展示"
    :extra="`${totalCount.toLocaleString()} 条 / ${totalKm.toLocaleString()} km`"
  >
    <div class="mode-switch" style="align-self: flex-start; margin-bottom: 8px">
      <button :class="{ active: state.roadColorBy === 'class' }" @click="state.roadColorBy = 'class'">
        按等级
      </button>
      <button :class="{ active: state.roadColorBy === 'congestion' }" @click="state.roadColorBy = 'congestion'">
        按拥堵
      </button>
    </div>

    <div class="class-list">
      <div
        v-for="r in roadRows"
        :key="r.key"
        class="class-row"
        :class="{ focus: state.focusClass === r.key, dim: state.focusClass && state.focusClass !== r.key }"
        @click="focus(r.key)"
      >
        <span class="swatch" :style="{ background: r.color }"></span>
        <span class="nm">{{ r.key }}</span>
        <span class="km">{{ r.km.toLocaleString() }}<span class="u"> km</span></span>
        <span class="cnt">{{ r.count.toLocaleString() }} 条</span>
      </div>
    </div>
    <div class="hint-line">
      {{ state.focusClass ? `正在高亮「${state.focusClass}」，再点一次恢复` : '点击某一等级可在地图上高亮显示' }}
    </div>
  </PanelBox>

  <!-- 轨道交通管理 -->
  <PanelBox
    v-else-if="state.mode === 'metro'"
    title="轨道交通线路"
    :extra="`${onLines} / ${lines.length} 条显示中`"
  >
    <div class="class-list">
      <div
        v-for="l in lines"
        :key="l.line_no"
        class="class-row"
        :class="{ off: !state.metroLines[l.line_no] }"
        @click="toggleLine(l.line_no)"
      >
        <span class="swatch" :style="{ background: l.colour || '#4fa8ff' }"></span>
        <span class="nm">{{ l.line_no }}</span>
        <span class="km">{{ l.km }}<span class="u"> km</span></span>
        <span class="cnt">{{ l.segs }} 段</span>
      </div>
    </div>
    <div class="hint-line">
      点击线路可开关该线；共 {{ transit.metro_stations ?? '--' }} 座车站
    </div>
    <div class="mini-ops">
      <button @click="allLines(true)">全部线路</button>
      <button @click="allLines(false)">隐藏全部</button>
    </div>
  </PanelBox>

  <!-- 公交运行管理 -->
  <PanelBox
    v-else
    title="公交运行图层"
    :extra="`${transit.bus_routes ?? '--'} 条线路`"
  >
    <div class="metric-grid c2" style="margin-bottom: 9px">
      <div class="metric">
        <div class="lbl">公交线路</div>
        <div class="val">{{ transit.bus_routes ?? '--' }}<span class="unit">条</span></div>
      </div>
      <div class="metric accent2">
        <div class="lbl">公交站点</div>
        <div class="val">{{ transit.bus_stops ?? '--' }}<span class="unit">个</span></div>
      </div>
    </div>
    <div class="sub-title">运营单位分布</div>
    <div class="rank-list" style="flex: 1">
      <div v-for="n in busNetworks" :key="n.network" class="mini-row">
        <span class="nm">{{ n.network }}</span>
        <span class="bar-wrap">
          <i class="bar" :style="{ width: (n.routes / busNetworks[0].routes) * 100 + '%' }"></i>
        </span>
        <span class="num">{{ n.routes }}</span>
      </div>
      <div v-if="!busNetworks.length" class="empty-tip">暂无数据</div>
    </div>
    <div class="hint-line">在全屏地图的「图层控制」里可开关公交线路与站点</div>
  </PanelBox>
</template>
