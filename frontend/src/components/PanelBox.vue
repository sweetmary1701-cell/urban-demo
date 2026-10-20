<script setup>
defineProps({
  title: { type: String, default: '' },
  extra: { type: String, default: '' },
})
</script>

<template>
  <section class="panel">
    <header class="panel-title">
      <span class="tl"><i class="bar"></i>{{ title }}</span>
      <span class="extra">{{ extra }}<slot name="extra"></slot></span>
    </header>
    <div class="panel-body"><slot></slot></div>
  </section>
</template>
