// Apply the saved theme before the first paint. No credentials are accessed.
(() => {
 let theme='light';
 try { if(localStorage.getItem('qr-theme')==='dark') theme='dark'; } catch {}
 document.documentElement.dataset.theme=theme;
 document.querySelector('meta[name="theme-color"]')?.setAttribute('content',theme==='dark'?'#181c19':'#faf8f5');
})();
