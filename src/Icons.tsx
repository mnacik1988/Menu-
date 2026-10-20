import type { ReactNode } from 'react';
export type IconName='menu'|'table'|'cart'|'call'|'bill'|'plus'|'close'|'back'|'search'|'user'|'orders'|'leaf';
const shapes:Record<IconName,ReactNode>={
 menu:<><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></>,
 table:<><path d="M3 9h18M5 9V6h14v3M6 9v12m12-12v12M5 15h14"/></>,
 cart:<><path d="M3 3h2l3 12h11l2-8H6"/><circle cx="9" cy="20" r="1"/><circle cx="18" cy="20" r="1"/></>,
 call:<path d="m8 3-4 2c-2 8 7 17 15 15l2-4-5-3-2 3c-3-1-5-3-6-6l3-2-3-5Z"/>,
 bill:<><rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 7h6M9 11h6m-6 4h3"/></>,
 plus:<path d="M12 5v14M5 12h14"/>,close:<path d="m6 6 12 12M6 18 18 6"/>,back:<path d="m10 5-7 7 7 7M3 12h18"/>,
 search:<><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/></>,
 user:<><circle cx="12" cy="7" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/></>,
 orders:<><rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 7h6M9 11h6m-6 4h6"/></>,
 leaf:<><path d="M20 3C7 2 2 10 6 17c7 4 15-1 14-14ZM4 21l11-11"/></>
};
export function Icon({name,className=''}:{name:IconName,className?:string}){return <svg className={'icon '+className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{shapes[name]}</svg>;}
