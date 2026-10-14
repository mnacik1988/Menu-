import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
async function load(name,env,client){let handler;const src=await readFile(new URL(`../supabase/functions/${name}/index.ts`,import.meta.url),'utf8');const transformed=ts.transpileModule(src,{compilerOptions:{module:ts.ModuleKind.CommonJS,esModuleInterop:true,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});assert.equal((transformed.diagnostics??[]).filter(d=>d.category===ts.DiagnosticCategory.Error).length,0);
 new Function('require','exports','Deno',transformed.outputText)(name=>name.includes('supabase-js')?{createClient:()=>client}: {}, {}, {env:{get:k=>env[k]},serve:h=>{handler=h;}});return handler;}
test('push worker requires a configured secret and POST, including when env is empty',async()=>{
 const handler=await load('push-dispatch',{},null);assert.equal((await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer undefined'}}))).status,401);
 const configured=await load('push-dispatch',{PUSH_DISPATCH_SECRET:'test-only'},null);assert.equal((await configured(new Request('https://example.test',{headers:{Authorization:'Bearer test-only'}}))).status,401);
 assert.equal((await configured(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer test-only'}}))).status,503);
});
test('employee invitations cannot reach Auth Admin without an authenticated restaurant admin',async()=>{
 let sent=0;const unauthorized={auth:{getUser:async()=>({data:{user:null},error:new Error('invalid')})}};
 const handler=await load('invite-staff',{APP_ORIGIN:'https://example.test'},unauthorized);assert.equal((await handler(new Request('https://example.test',{method:'POST'}))).status,401);
 const waiter={auth:{getUser:async()=>({data:{user:{id:'test'}},error:null}),admin:{inviteUserByEmail:()=>{sent++;}}},from(table){return {select(){return this;},eq(){return this;},async single(){return {data:table==='restaurants'?{status:'active'}:{role:'waiter',active:true}};}};}};
 const limited=await load('invite-staff',{APP_ORIGIN:'https://example.test'},waiter);assert.equal((await limited(new Request('https://example.test',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({restaurant_id:'test',email:'test@example.test'})}))).status,403);assert.equal(sent,0);
});
