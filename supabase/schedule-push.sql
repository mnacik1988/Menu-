-- Run AFTER creating two Vault secrets in the Supabase dashboard:
-- qr_waiter_project_url = your https://PROJECT.supabase.co
-- qr_waiter_push_secret = the same random secret as PUSH_DISPATCH_SECRET in Edge Functions.
create extension if not exists pg_net with schema extensions;
select cron.schedule('qr-waiter-push','* * * * *',$job$
 select net.http_post(
  url:=(select decrypted_secret from vault.decrypted_secrets where name='qr_waiter_project_url')||'/functions/v1/push-dispatch',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='qr_waiter_push_secret')),
  body:='{}'::jsonb
 );
$job$);
