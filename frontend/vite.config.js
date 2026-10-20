import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    host: '127.0.0.1',
    // 开发代理：把两类后端服务都挂到同源下，浏览器视角就没有跨域问题
    proxy: {
      // 业务统计接口 -> FastAPI
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
      // 地理数据服务 -> GeoServer（WMS / WFS / GetFeatureInfo 全部走这里）
      '/geoserver': {
        target: 'http://localhost:8086',
        changeOrigin: true,
      },
    },
  },
})
