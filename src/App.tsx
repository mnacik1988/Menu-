import { lazy, useEffect, useState } from 'react';
import { configured, db, rows, rpc, type Row } from './api';
import { translator, type Lang } from './i18n';
import { Field, Form, Button, type Run } from './ui';
const Guest=lazy(()=>import('./Guest').then(m=>({default:m.Guest})));
const Staff=lazy(()=>import('./Staff').then(m=>({default:m.Staff})));

export default function App() {
 const [lang,setLang]=useState<Lang>((localStorage.getItem('qr-language') as Lang)||'uk'); const t=translator(lang);
 const [user,setUser]=useState<Row|null>(null),[memberships,setMemberships]=useState<Row[]>([]),[rest,setRest]=useState('');
 const [superAdmin,setSuper]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[authReady,setAuthReady]=useState(!configured);
 const [register,setRegister]=useState(false),[install,setInstall]=useState<any>(null),[online,setOnline]=useState(navigator.onLine);
 const [theme,setTheme]=useState<'light'|'dark'>(()=>document.documentElement.dataset.theme==='dark'?'dark':'light');
 useEffect(()=>{
  document.documentElement.dataset.theme=theme;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content',theme==='dark'?'#181c19':'#faf8f5');
  try{localStorage.setItem('qr-theme',theme);}catch{/* Theme still works when storage is unavailable. */}
 },[theme]);
 const qr=new URLSearchParams(location.search).get('qr');
 const run:Run=async(job,success)=>{setError('');setNotice('');setBusy(true);try {if(!navigator.onLine) throw new Error('OFFLINE'); const result=await job(); if(success) setNotice(success); return result ?? true;}
 catch(e) {const msg=e instanceof Error?e.message:String(e); const key=Object.keys(errorCodes).find(c=>msg.includes(c));setError(msg==='OFFLINE'?t('offline'):key?t('error_'+key):msg.includes('fetch')?t('networkError'):msg);return false;}
 finally{setBusy(false);}};
 useEffect(()=>{document.documentElement.lang=lang;localStorage.setItem('qr-language',lang);},[lang]);
 useEffect(()=>{if(!db)return; let alive=true;
  db.auth.getSession().then(({data})=>{if(alive){setUser(data.session?.user??null);setAuthReady(true);}});
  const {data:{subscription}}=db.auth.onAuthStateChange((_event,session)=>{setUser(session?.user??null);setAuthReady(true);});
  return()=>{alive=false;subscription.unsubscribe();};},[]);
 useEffect(()=>{if(!user||!db){setMemberships([]);return;}let alive=true;
  Promise.all([db.from('restaurant_staff').select('*,restaurants(id,name,status)').eq('user_id',user.id).eq('active',true),rpc('is_super')]).then(([result,isSuper])=>{
   if(!alive)return;if(result.error){setError(result.error.message);return;}const list=result.data??[];setMemberships(list);setSuper(isSuper);
   const saved=localStorage.getItem('qr-restaurant');setRest(list.some(m=>m.restaurant_id===saved)?saved!:list[0]?.restaurant_id??'');
  }).catch(e=>setError(String(e)));return()=>{alive=false;};},[user]);
 useEffect(()=>{const change=()=>setOnline(navigator.onLine);const event=(e:Event)=>{e.preventDefault();setInstall(e);};window.addEventListener('online',change);window.addEventListener('offline',change);window.addEventListener('beforeinstallprompt',event);return()=>{window.removeEventListener('online',change);window.removeEventListener('offline',change);window.removeEventListener('beforeinstallprompt',event);};},[]);
 useEffect(()=>{if(!notice)return;const id=setTimeout(()=>setNotice(''),4500);return()=>clearTimeout(id);},[notice]);
 async function auth(d:Row) {return run(async()=>{if(register){const {error}=await db!.auth.signUp({email:d.email,password:d.password,options:{emailRedirectTo:location.origin,data:{name:d.name}}});if(error)throw error;setNotice(t('checkEmail'));}
 else{const {error}=await db!.auth.signInWithPassword({email:d.email,password:d.password});if(error)throw error;}});}
 async function logout() {await run(async()=>{const reg=await navigator.serviceWorker?.getRegistration();const sub=await reg?.pushManager.getSubscription();if(sub){await db!.from('push_subscriptions').delete().eq('endpoint',sub.endpoint);await sub.unsubscribe();}await db!.auth.signOut();setUser(null);setRest('');});}
 const member=memberships.find(m=>m.restaurant_id===rest);
 return <><header className="topbar"><a className="logo" href="/"><span className="logo-mark" aria-hidden="true"><svg viewBox="0 0 32 32" fill="none"><rect x="4" y="4" width="8" height="8" rx="2"/><rect x="20" y="4" width="8" height="8" rx="2"/><rect x="4" y="20" width="8" height="8" rx="2"/><path d="M20 20h4v4h4v4h-8v-8Z"/></svg></span><span>QR <b>Waiter</b><small>{t('brand')}</small></span></a>
 <div className="top-actions"><button type="button" className="theme-toggle" onClick={()=>setTheme(theme==='light'?'dark':'light')} aria-label={t(theme==='light'?'darkTheme':'lightTheme')} title={t(theme==='light'?'darkTheme':'lightTheme')} aria-pressed={theme==='dark'}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{theme==='light'?<path d="M20.4 13.2A8.5 8.5 0 0 1 10.8 3.6 8.5 8.5 0 1 0 20.4 13.2Z"/>:<><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4m0-14.2-1.4 1.4M6.3 17.7l-1.4 1.4"/></>}</svg></button><label className="sr-only" htmlFor="language">{t('language')}</label><select id="language" value={lang} onChange={e=>setLang(e.target.value as Lang)}><option value="uk">UA</option><option value="ru">RU</option><option value="en">EN</option></select>
 {install&&<Button secondary onClick={()=>{install.prompt();setInstall(null);}}>{t('install')}</Button>}
 {user&&!qr&&<Button secondary onClick={logout}>{t('logout')}</Button>}{qr&&<a className="small-link" href="/">{t('staffLogin')}</a>}</div></header>
 {!online&&<div className="message error" role="status">{t('offline')}</div>}
 {error&&<div className="message error" role="alert"><span>{error}</span><button type="button" className="ghost" onClick={()=>setError('')} aria-label={t('close')}>×</button></div>}
 {notice&&<div className="message success" role="status">{notice}</div>}
 {!configured?<main className="welcome"><div className="eyebrow">QR WAITER · MVP</div><h1>{t('setup')}</h1><p>{t('setupBody')}</p><div className="setup-code">VITE_SUPABASE_URL<br/>VITE_SUPABASE_ANON_KEY</div><p className="muted">{t('setupNoData')}</p></main>:
 qr?<Guest qr={qr} t={t} lang={lang} run={run} busy={busy}/>:
 !authReady?<main className="welcome">{t('loading')}</main>:
 !user?<main className="welcome login"><div className="login-emblem" aria-hidden="true"><svg viewBox="0 0 64 64" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round"><circle cx="32" cy="32" r="21"/><circle cx="32" cy="32" r="15"/><path d="M6 18v13m-3-13v8c0 3 6 3 6 0v-8M6 31v15m51-28v28m0-28c-6 5-6 15 0 15"/></svg></div><div className="eyebrow">QR WAITER</div><h1>{t(register?'register':'login')}</h1><p>{t('brand')}</p>
 <Form onSubmit={auth} className="stack">{register&&<Field label={t('name')}><input name="name" required maxLength={100} autoComplete="name"/></Field>}
 <Field label={t('email')}><input type="email" name="email" required autoComplete="email"/></Field><Field label={t('password')}><input name="password" type="password" required minLength={register?10:1} autoComplete={register?'new-password':'current-password'}/></Field><Button disabled={busy}>{t(register?'register':'login')}</Button></Form>
 <div className="row login-links"><Button secondary onClick={()=>setRegister(!register)}>{t(register?'login':'register')}</Button><Button secondary onClick={()=>run(async()=>{const email=prompt(t('email'));if(email){const {error}=await db!.auth.resetPasswordForEmail(email,{redirectTo:location.origin});if(error)throw error;setNotice(t('checkEmail'));}})}>{t('forgot')}</Button></div></main>:
 <><div className="restaurant-switch"><span>{user.email}</span>{memberships.length>0&&<select aria-label={t('restaurant')} value={rest} onChange={e=>{setRest(e.target.value);localStorage.setItem('qr-restaurant',e.target.value);}}>{memberships.map(m=><option key={m.restaurant_id} value={m.restaurant_id}>{m.restaurants.name}</option>)}</select>}</div>
 {member||superAdmin?<Staff key={rest} rest={rest} member={member} superAdmin={superAdmin} user={user} t={t} lang={lang} run={run} busy={busy}/>:<main className="welcome"><h1>{t('createRestaurant')}</h1><Form className="stack" onSubmit={d=>run(async()=>{await rpc('create_restaurant',{p_name:d.restaurant,p_staff_name:d.name});setUser({...user});})}><Field label={t('restaurantName')}><input name="restaurant" required maxLength={120}/></Field><Field label={t('name')}><input name="name" required defaultValue={user.user_metadata?.name??''} maxLength={100}/></Field><Button disabled={busy}>{t('createRestaurant')}</Button></Form><PasswordForm t={t} run={run} busy={busy}/></main>}</>}
 </>;
}
export function PasswordForm({t,run,busy}:{t:(k:string)=>string,run:Run,busy:boolean}){return <details className="panel"><summary>{t('changePassword')}</summary><Form onSubmit={d=>run(async()=>{const {error}=await db!.auth.updateUser({password:d.password});if(error)throw error;},t('operationOk'))}><Field label={t('passwordHint')}><input type="password" name="password" required minLength={10} autoComplete="new-password"/></Field><Button disabled={busy}>{t('save')}</Button></Form></details>;}
const errorCodes=Object.fromEntries(['FORBIDDEN','PRICE_CHANGED','ITEM_UNAVAILABLE','SESSION_INVALID','SESSION_CLOSED','TABLE_NOT_READY','UNFINISHED_ORDERS','NO_WAITER','RATE_LIMIT','INVALID_TRANSITION','PRESENCE_EXPIRED','QR_INACTIVE','CURRENCY_LOCKED','RESTAURANT_SUSPENDED'].map(x=>[x,true]));
