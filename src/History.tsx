import { useState } from 'react';
import type { Row } from './api';
import { Empty, type T } from './ui';
export function History({events,shifts,staff,t,lang}:{events:Row[],shifts:Row[],staff:Row[],t:T,lang:string}) {
 const [shift,setShift]=useState('');const selected=shifts.find(s=>s.id===shift);
 const visible=events.filter(e=>!selected||(Date.parse(e.at)>=Date.parse(selected.started_at)&&(!selected.ended_at||Date.parse(e.at)<Date.parse(selected.ended_at)))).sort((a,b)=>Date.parse(b.at)-Date.parse(a.at));
 function detail(e:Row){const p=e.payload;return [p.status?t(p.status):'',p.waiter_id?staff.find(s=>s.user_id===p.waiter_id)?.name:'',p.state?t(p.state):'',p.reason??''].filter(Boolean).join(' · ');}
 return <><div className="section-header"><h1>{t('history')}</h1><select aria-label={t('shifts')} value={shift} onChange={e=>setShift(e.target.value)}><option value="">{t('all')}</option>{shifts.map(s=><option key={s.id} value={s.id}>{s.name} · {new Date(s.started_at).toLocaleDateString(lang)}</option>)}</select></div>{visible.length===0?<Empty t={t}/>:<div className="panel table-scroll"><table><thead><tr><th>{t('time')}</th><th>{t('event')}</th><th>{t('actor')}</th><th>{t('details')}</th></tr></thead><tbody>{visible.map(e=><tr key={e.id}><td>{new Date(e.at).toLocaleString(lang)}</td><td>{t('event_'+e.kind)}<small>{e.order_id&&'#'+e.order_id.slice(0,6)}</small></td><td>{staff.find(u=>u.user_id===e.actor_id)?.name??'—'}</td><td>{detail(e)||'—'}</td></tr>)}</tbody></table></div>}</>;
}
