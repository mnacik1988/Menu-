import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname,basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {isPrivatePath} from '../scripts/check-secrets.mjs';

test('private document names and environment files are blocked; source templates are allowed',()=>{
 for(const path of ['Пароли и АПИ.txt','nested/Пароли и АПИ.docx','nested/пароли и апи.txt','.env','.env.production','nested/private.key'])assert.equal(isPrivatePath(path),true,path);
 for(const path of ['.env.example','src/api.ts','README.md'])assert.equal(isPrivatePath(path),false,path);
});
test('forced staging of a private document fails the check without reading its contents',()=>{
 const root=realpathSync(tmpdir());const folder=mkdtempSync(join(root,'qr-waiter-secret-test-'));
 const script=fileURLToPath(new URL('../scripts/check-secrets.mjs',import.meta.url));
 try{
  execFileSync('git',['init',folder],{stdio:'ignore'});
  writeFileSync(join(folder,'.env.example'),'VITE_SUPABASE_URL=\n');
  execFileSync('git',['-C',folder,'add','--','.env.example'],{stdio:'ignore'});
  assert.equal(spawnSync(process.execPath,[script],{cwd:folder}).status,0);
  const marker='synthetic-test-content-must-not-be-printed';
  writeFileSync(join(folder,'Пароли и АПИ.txt'),marker);
  execFileSync('git',['-C',folder,'add','-f','--','Пароли и АПИ.txt'],{stdio:'ignore'});
  const result=spawnSync(process.execPath,[script],{cwd:folder,encoding:'utf8'});
  assert.equal(result.status,1);assert.ok(result.stderr.includes('private files'));assert.ok(!result.stderr.includes(marker));assert.ok(!result.stdout.includes(marker));
 }finally{
  // Windows cleanup: resolve and verify the exact temporary target before deletion.
  const target=realpathSync(folder);
  if(dirname(target)!==root||!basename(target).startsWith('qr-waiter-secret-test-'))throw new Error('Unexpected temporary path');
  rmSync(target,{recursive:true,force:true});
 }
});
