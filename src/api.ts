import { createClient } from '@supabase/supabase-js';
export const configured = Boolean(import.meta.env.VITE_SUPABASE_URL && import.meta.env.VITE_SUPABASE_ANON_KEY);
export const db = configured ? createClient(import.meta.env.VITE_SUPABASE_URL, import.meta.env.VITE_SUPABASE_ANON_KEY) : null;
export type Row = Record<string, any>;
export async function rpc(name: string, args: Row = {}) {
 if (!db) throw new Error('NOT_CONFIGURED');
 const { data, error } = await db.rpc(name, args);
 if (error) throw new Error(error.message); return data;
}
const pendingKeys = new Map<string, string>();
export async function command(name: string, args: Row) {
 const signature = name + JSON.stringify(args);
 const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(signature))),b=>b.toString(16).padStart(2,'0')).join('');
 const storageKey='command:'+hash;
 const key = pendingKeys.get(signature) ?? sessionStorage.getItem(storageKey) ?? crypto.randomUUID(); pendingKeys.set(signature, key); sessionStorage.setItem(storageKey,key);
 const result = await rpc(name, { ...args, p_key: key });
 pendingKeys.delete(signature); sessionStorage.removeItem(storageKey); return result;
}
export async function rows(table: string, rest?: string, select = '*') {
 if (!db) throw new Error('NOT_CONFIGURED');
 const result:Row[]=[];
 const orderKey=table==='restaurant_staff'||table==='super_admins'?'user_id':table==='restaurant_settings'?'restaurant_id':'id';
 for(let offset=0;;offset+=1000){let query=db.from(table).select(select).order(orderKey).range(offset,offset+999);if(rest)query=query.eq('restaurant_id',rest);
 const {data,error}=await query;if(error)throw new Error(error.message);result.push(...(data??[]) as Row[]);if((data??[]).length<1000)break;}
 return result;
}
export function ageColor(seconds: number) { return seconds < 60 ? 'green' : seconds <= 120 ? 'yellow' : 'red'; }
export function secondsSince(at: string, serverNow = Date.now()) { return Math.max(0, (serverNow - Date.parse(at)) / 1000); }
export function formatDuration(value: number | null | undefined) {
 if (value == null) return '—'; const s = Math.floor(value);
 return s < 60 ? `${s}s` : `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
export function guestLink(qr: string) { return `${import.meta.env.VITE_APP_URL || location.origin}/?qr=${encodeURIComponent(qr)}`; }
