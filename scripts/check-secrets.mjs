import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function isPrivatePath(path) {
 const name=path.replaceAll('\\','/').split('/').pop();
 if(name==='.env.example') return false;
 return /^(?:Пароли и АПИ.*|\.env(?:\..*)?|.*\.(?:pem|key|p12|pfx))$/iu.test(name);
}

export function checkIndex() {
 // Read only names from the index. Never read or echo credential contents.
 const names=execFileSync('git',['ls-files','--cached','-z'],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).split('\0').filter(Boolean);
 const privateNames=names.filter(isPrivatePath);
 if(privateNames.length){
  console.error('Commit blocked: private files are staged. Remove them from the index; keep local copies.');
  for(const name of privateNames)console.error(JSON.stringify(name));
  return 1;
 }
 return 0;
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{process.exitCode=checkIndex();}
 catch{console.error('Unable to verify the Git index. Commit blocked.');process.exitCode=1;}
}
