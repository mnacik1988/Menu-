import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './styles.css';
import './tap-theme.css';
ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><React.Suspense fallback={<main className="welcome">QR Waiter…</main>}><App/></React.Suspense></React.StrictMode>);
if(import.meta.env.PROD && 'serviceWorker' in navigator) window.addEventListener('load',()=>{navigator.serviceWorker.register('/sw.js').catch(()=>{/* App works without PWA permissions. */});});

if(import.meta.env.DEV && 'serviceWorker' in navigator){navigator.serviceWorker.getRegistrations().then(regs=>Promise.all(regs.filter(r=>r.active?.scriptURL===location.origin+'/sw.js').map(r=>r.unregister()))).then(()=>caches.keys()).then(keys=>Promise.all(keys.filter(k=>k.startsWith('qr-waiter-shell-')).map(k=>caches.delete(k)))).catch(()=>{});}
