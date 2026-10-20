<script setup>
import { computed } from 'vue'
import { applyMode, state } from '../state'

const MODES = [
  { key: 'road', label: '道路交通管理' },
  { key: 'bus', label: '公交运行管理' },
  { key: 'metro', label: '轨道交通管理' },
]

const dateText = computed(() => {
  const d = state.now
  const w = '日一二三四五六'[d.getDay()]
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} 星期${w}`
})
const timeText = computed(() => {
  const d = state.now
  return [d.getHours(), d.getMinutes(), d.getSeconds()]
    .map((n) => String(n).padStart(2, '0'))
    .join(':')
})

function switchMode(m) {
  state.mode = m
  state.selectedDistrict = null
  applyMode(m)
}
</script>

<template>
  <header class="screen-header">
    <div class="header-side">
      <div>
        <div class="title-main">苏州智慧交通可视化平台</div>
        <div class="title-sub">SUZHOU INTELLIGENT TRANSPORT · VISUALIZATION</div>
      </div>
    </div>

    <div class="mode-switch">
      <button
        v-for="m in MODES"
        :key="m.key"
        :class="{ active: state.mode === m.key }"
        @click="switchMode(m.key)"
      >
        {{ m.label }}
      </button>
    </div>

    <div class="header-side right">
      <div style="text-align: right">
        <div class="clock">{{ timeText }}<small>{{ dateText }}</small></div>
      </div>
    </div>
  </header>
</template>
