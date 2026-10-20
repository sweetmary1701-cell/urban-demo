<script setup>
import { computed } from 'vue'
import { LAYER_CONTROLS } from '../config/layers'
import { setAllLayers, state } from '../state'

const onCount = computed(() => Object.values(state.visible).filter(Boolean).length)

function toggle(key) {
  state.visible[key] = !state.visible[key]
}
</script>

<template>
  <div class="layer-ctrl">
    <div class="lc-head">
      <span>图层控制</span>
      <span class="lc-count">{{ onCount }} / {{ LAYER_CONTROLS.length }}</span>
    </div>

    <div class="lc-list">
      <div
        v-for="l in LAYER_CONTROLS"
        :key="l.key"
        class="lc-item"
        :class="{ on: state.visible[l.key] }"
        @click="toggle(l.key)"
      >
        <span class="lc-mark" :class="l.shape" :style="{ background: l.color }"></span>
        <span class="lc-name">{{ l.label }}</span>
        <span class="lc-switch"><i></i></span>
      </div>
    </div>

    <div class="lc-ops">
      <button @click="setAllLayers(true)">全部开启</button>
      <button class="danger" @click="setAllLayers(false)">全部关闭</button>
    </div>
  </div>
</template>
