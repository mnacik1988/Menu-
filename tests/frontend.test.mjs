import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
import { createRequire } from 'node:module';
import jsQR from 'jsqr';
import { PNG } from 'pngjs';
const require=createRequire(import.meta.url);
const source=await readFile(new URL('../src/api.ts',import.meta.url),'utf8');
// Compile only the pure timer helpers, without browser/Supabase initialization.
const helpers=source.slice(source.indexOf('export function ageColor'),source.indexOf('export function guestLink'));
const compiled=ts.transpileModule(helpers,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const exports={};new Function('exports',compiled)(exports);
test('timer boundaries and accepted reaction formatting',()=>{assert.equal(exports.ageColor(59),'green');assert.equal(exports.ageColor(60),'yellow');assert.equal(exports.ageColor(120),'yellow');assert.equal(exports.ageColor(121),'red');assert.equal(exports.formatDuration(null),'—');assert.equal(exports.formatDuration(125),'2:05');});
test('all UI languages contain the same keys',async()=>{const src=await readFile(new URL('../src/i18n.ts',import.meta.url),'utf8');const js=ts.transpileModule(src+'\nexport const dictionaries={uk,ru,en};',{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;const out={};new Function('exports',js)(out);const keys=Object.keys(out.dictionaries.uk);for(const lang of ['ru','en'])for(const key of keys)assert.ok(out.dictionaries[lang][key],`${lang}: ${key}`);});
test('the exported PNG decodes to the exact table link and embeds into a printable PDF',async()=>{
 const src=await readFile(new URL('../src/qr-export.ts',import.meta.url),'utf8');const compiled=ts.transpileModule(src,{compilerOptions:{module:ts.ModuleKind.CommonJS,esModuleInterop:true,target:ts.ScriptTarget.ES2022}}).outputText;
 const out={};new Function('require','exports',compiled)(require,out);
 const id='a1655a66-4935-4d15-a615-edc3c38082ad';const link='https://restaurant.example/?qr='+id;
 const image=await out.encodeQR(link);const png=PNG.sync.read(Buffer.from(image.split(',')[1],'base64'));const decoded=jsQR(new Uint8ClampedArray(png.data),png.width,png.height);assert.equal(decoded?.data,link);
 const doc=await out.createQRDocument(image,image,id);doc.autoPrint();const pdf=Buffer.from(doc.output('arraybuffer'));assert.equal(pdf.subarray(0,5).toString(),'%PDF-');assert.ok(pdf.toString('latin1').includes('/Subtype /Image'));assert.ok(pdf.toString('latin1').includes(id));
});
