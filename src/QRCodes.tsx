import { useEffect, useState } from 'react';
import { encodeQR,createQRDocument } from './qr-export';
import { guestLink, type Row } from './api';
import { Button, type T, type Run } from './ui';
export function QRCard({qr,label,t,run,busy,change}:{qr:Row,label:string,t:T,run:Run,busy:boolean,change:(active:boolean)=>void}) {
 const [image,setImage]=useState(''); const link=guestLink(qr.id);
 useEffect(()=>{let alive=true;encodeQR(link).then(img=>{if(alive)setImage(img);});return()=>{alive=false;};},[link]);
 async function pdf(print=false){
  const canvas=document.createElement('canvas');canvas.width=1000;canvas.height=100;const ctx=canvas.getContext('2d')!;ctx.fillStyle='white';ctx.fillRect(0,0,1000,100);ctx.fillStyle='#20332b';ctx.font='40px sans-serif';ctx.textAlign='center';ctx.fillText(label,500,60,940);const doc=await createQRDocument(image,canvas.toDataURL('image/png'),qr.id);
  if(print){doc.autoPrint();const url=URL.createObjectURL(doc.output('blob'));window.open(url,'_blank','noopener');setTimeout(()=>URL.revokeObjectURL(url),60000);}else doc.save(`qr-${qr.id}.pdf`);}
 return <article className="qr-card"><div><strong>{label}</strong><small className="muted">{qr.active?t('active'):t('suspended')}</small></div>{image&&<img src={image} alt={`QR ${label}`} width={180} height={180}/>}<a href={link} target="_blank" rel="noreferrer">{t('openMenu')} ↗</a><div className="row"><a className="button secondary" href={image} download={`qr-${qr.id}.png`}>{t('downloadPNG')}</a><Button secondary onClick={()=>run(()=>pdf())} disabled={!image}>{t('downloadPDF')}</Button><Button secondary onClick={()=>run(()=>pdf(true))} disabled={!image}>{t('print')}</Button></div><Button secondary disabled={busy} onClick={()=>change(!qr.active)}>{t(qr.active?'deactivate':'activate')}</Button></article>;
}
