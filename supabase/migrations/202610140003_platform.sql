-- Supabase-specific infrastructure, separate from portable PostgreSQL business tests.
create extension if not exists pg_cron;
select cron.schedule('qr-waiter-waiting','10 seconds','select public.tick_waiting_orders()');
alter publication supabase_realtime add table public.orders,public.notifications,public.service_requests,public.dining_tables,public.table_sessions;
-- No presence_requests replication: its row includes the guest token hash.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('menu-photos','menu-photos',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy menu_photo_insert on storage.objects for insert to authenticated
with check(bucket_id='menu-photos' and public.my_role(((storage.foldername(name))[1])::uuid)='admin');
create policy menu_photo_delete on storage.objects for delete to authenticated
using(bucket_id='menu-photos' and public.my_role(((storage.foldername(name))[1])::uuid)='admin');
create policy menu_photo_manage_read on storage.objects for select to authenticated
using(bucket_id='menu-photos' and public.my_role(((storage.foldername(name))[1])::uuid)='admin');
-- An unattended push dispatcher is scheduled separately after setting Vault secrets;
-- see supabase/schedule-push.sql. Waiting alerts never depend on this channel.
