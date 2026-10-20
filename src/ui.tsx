import type { FormEvent, ReactNode } from 'react';
import type { Row } from './api';
export type T = (key: string) => string;
export type Run = (job: () => Promise<any>, success?: string) => Promise<any>;
export function Field({label,children}:{label:string,children:ReactNode}) { return <label className="field"><span>{label}</span>{children}</label>; }
export function Form({children,onSubmit,reset=false,className='form-grid'}:{children:ReactNode,onSubmit:(data:Row)=>Promise<any>,reset?:boolean,className?:string}) {
 async function submit(e:FormEvent<HTMLFormElement>) { e.preventDefault(); const form=e.currentTarget;
  const result=await onSubmit(Object.fromEntries(new FormData(form))); if(result!==false && reset) form.reset(); }
 return <form className={className} onSubmit={submit}>{children}</form>;
}
export function Empty({t}:{t:T}) {return <div className="empty"><span className="empty-symbol">◇</span><p>{t('empty')}</p></div>;}
export function Badge({value,t}:{value:string,t:T}) {return <span className={`badge ${value}`}>{t(value)}</span>;}
export function Button({children,onClick,disabled=false,secondary=false}:{children:ReactNode,onClick?:()=>void,disabled?:boolean,secondary?:boolean}) {return <button type={onClick?'button':'submit'} className={secondary?'secondary':''} onClick={onClick} disabled={disabled}>{children}</button>;}
