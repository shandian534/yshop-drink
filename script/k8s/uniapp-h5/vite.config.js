import { defineConfig } from 'vite'
import uni from '@dcloudio/vite-plugin-uni'

export default defineConfig({
  plugins: [uni()],
  server: {
    port: 3000,
    host: '0.0.0.0'
  },
  build: {
    outDir: 'dist/build/h5',
    assetsDir: 'static',
    // H5 构建配置
    rollupOptions: {
      output: {
        manualChunks: {}
      }
    }
  }
})
