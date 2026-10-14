import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './styles.css';
ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><React.Suspense fallback={<main className="welcome">QR Waiter…</main>}><App/></React.Suspense></React.StrictMode>);
if('serviceWorker' in navigator) window.addEventListener('load',()=>{navigator.serviceWorker.register('/sw.js').catch(()=>{/* App works without PWA permissions. */});});
