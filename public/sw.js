const CACHE='qr-waiter-shell-v2';
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(['/','/icon.svg','/theme-init.js']))));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('qr-waiter-shell-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
 const url=new URL(e.request.url);if(url.origin!==self.location.origin||e.request.method!=='GET')return;
 if(e.request.mode==='navigate'){e.respondWith(fetch(e.request).then(r=>{if(r.ok){const copy=r.clone();caches.open(CACHE).then(c=>c.put('/',copy));}return r;}).catch(()=>caches.match('/')));return;}
 if(/\.(js|css|svg|png)$/.test(url.pathname))e.respondWith(caches.match(e.request).then(cached=>cached||fetch(e.request).then(r=>{if(r.ok)caches.open(CACHE).then(c=>c.put(e.request,r.clone()));return r;})));
});
self.addEventListener('push',e=>{let data={};try{data=e.data?.json()??{};}catch{return;}e.waitUntil(self.registration.showNotification(data.title||'QR Waiter',{body:data.body,tag:data.id,icon:'/icon.svg',data:{url:data.url||'/'}}));});
self.addEventListener('notificationclick',e=>{e.notification.close();e.waitUntil(self.clients.matchAll({type:'window'}).then(async clients=>{const existing=clients.find(c=>new URL(c.url).origin===self.location.origin);if(existing)return existing.focus();return self.clients.openWindow('/');}));});
