<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: [Number, String], default: '--' },
  unit: { type: String, default: '' },
  tone: { type: String, default: '' }, // '' | ok | warn | danger | accent2
})
</script>

<template>
  <div class="metric" :class="tone">
    <div class="lbl">{{ label }}</div>
    <div class="val">
      {{ value ?? '--' }}<span v-if="unit" class="unit">{{ unit }}</span>
    </div>
  </div>
</template>
