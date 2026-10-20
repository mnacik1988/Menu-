import QRCode from 'qrcode';
export function encodeQR(link:string){return QRCode.toDataURL(link,{width:600,margin:4,errorCorrectionLevel:'H'});}
export async function createQRDocument(image:string,labelImage:string,id:string){
 const {jsPDF}=await import('jspdf');
 const doc=new jsPDF({unit:'mm',format:'a5'});doc.setFontSize(18);doc.text('QR Waiter',74,24,{align:'center'});
 doc.addImage(image,'PNG',24,40,100,100);doc.addImage(labelImage,'PNG',24,145,100,10);doc.setFontSize(8);doc.text(id,74,164,{align:'center'});
 return doc;
}
