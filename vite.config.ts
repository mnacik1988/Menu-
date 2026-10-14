import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
export default defineConfig({ plugins: [react(), tailwindcss()], server: { port: 5173, fs: { deny: ['**/.env', '**/.env.*', '**/*.{crt,pem,key,p12,pfx}', '**/.git/**', '**/Пароли и АПИ*'] } } });
