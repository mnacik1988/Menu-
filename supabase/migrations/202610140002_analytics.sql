create function public.staff_analytics(p_rest uuid,p_period text default 'today',p_start date default null,p_end date default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare tz text; local_today date; start_at timestamptz; end_at timestamptz; people jsonb; hours jsonb; peaks jsonb; avg_reaction numeric;
begin
 if my_role(p_rest) is null then raise exception 'FORBIDDEN'; end if;
 select timezone into tz from restaurant_settings where restaurant_id=p_rest;
 local_today:=(clock_timestamp() at time zone tz)::date;
 case p_period
 when 'today' then p_start:=local_today; p_end:=local_today;
 when 'yesterday' then p_start:=local_today-1; p_end:=local_today-1;
 when 'week' then p_start:=local_today-6; p_end:=local_today;
 when 'month' then p_start:=date_trunc('month',local_today)::date; p_end:=local_today;
 when 'custom' then if p_start is null or p_end is null or p_end<p_start or p_end-p_start>366 then raise exception 'INVALID_PERIOD'; end if;
 else raise exception 'INVALID_PERIOD'; end case;
 start_at:=p_start::timestamp at time zone tz; end_at:=(p_end+1)::timestamp at time zone tz;
 select coalesce(jsonb_agg(jsonb_build_object(
 'user_id',u.user_id,'name',u.name,'role',u.role,'active',u.active,
 'received',(select count(distinct e.order_id) from events e where e.restaurant_id=p_rest and e.kind='order_received' and e.at>=start_at and e.at<end_at and e.payload->>'waiter_id'=u.user_id::text),
 'accepted',(select count(*) from orders o where o.restaurant_id=p_rest and o.accepted_by=u.user_id and o.accepted_at>=start_at and o.accepted_at<end_at),
 'avg_reaction',(select avg(o.reaction_seconds) from orders o where o.restaurant_id=p_rest and o.accepted_by=u.user_id and o.accepted_at>=start_at and o.accepted_at<end_at),
 'max_wait',(select max(o.reaction_seconds) from orders o where o.restaurant_id=p_rest and o.accepted_by=u.user_id and o.accepted_at>=start_at and o.accepted_at<end_at),
 'current_max_wait',(select max(extract(epoch from clock_timestamp()-o.created_at)) from orders o where o.restaurant_id=p_rest and o.waiter_id=u.user_id and o.status='new'),
 'overdue',(select count(*) from orders o where o.restaurant_id=p_rest and o.overdue_waiter_id=u.user_id and o.overdue_at>=start_at and o.overdue_at<end_at),
 'amount_minor',(select coalesce(sum(o.total_minor),0) from orders o where o.restaurant_id=p_rest and o.original_waiter_id=u.user_id and o.created_at>=start_at and o.created_at<end_at),
 'cancelled_amount_minor',(select coalesce(sum(o.total_minor),0) from orders o where o.restaurant_id=p_rest and o.original_waiter_id=u.user_id and o.created_at>=start_at and o.created_at<end_at and o.status='cancelled'),
 'cancelled',(select count(distinct e.order_id) from events e where e.restaurant_id=p_rest and e.kind='order_status' and e.payload->>'status'='cancelled' and e.payload->>'waiter_id'=u.user_id::text and e.at>=start_at and e.at<end_at),
 'calls',(select count(*) from events e where e.restaurant_id=p_rest and e.kind='request_created' and e.payload->>'kind'='call' and e.payload->>'waiter_id'=u.user_id::text and e.at>=start_at and e.at<end_at),
 'served_tables',(select count(*) from table_sessions s where s.restaurant_id=p_rest and s.closed_by=u.user_id and s.closed_at>=start_at and s.closed_at<end_at),
 'avg_service',(select avg(extract(epoch from s.closed_at-s.opened_at)) from table_sessions s where s.restaurant_id=p_rest and s.closed_by=u.user_id and s.closed_at>=start_at and s.closed_at<end_at),
 'active_tables',(select count(*) from table_sessions s where s.restaurant_id=p_rest and s.waiter_id=u.user_id and s.closed_at is null)
 ) order by u.name),'[]') into people from restaurant_staff u where u.restaurant_id=p_rest and (my_role(p_rest)='admin' or u.user_id=auth.uid());
 select avg(reaction_seconds) into avg_reaction from orders where restaurant_id=p_rest and accepted_at>=start_at and accepted_at<end_at;
 select coalesce(jsonb_agg(jsonb_build_object('at',h.bucket,'label',to_char(h.bucket at time zone tz,'DD.MM HH24:MI'),'count',h.n) order by h.bucket),'[]') into hours
 from(select date_trunc('hour',created_at,'UTC') as bucket,count(*) n from orders where restaurant_id=p_rest and created_at>=start_at and created_at<end_at group by 1) h;
 select coalesce(jsonb_agg(x),'[]') into peaks from jsonb_array_elements(hours) x where (x->>'count')::int=(select max((v->>'count')::int) from jsonb_array_elements(hours) v);
 return jsonb_build_object('start_at',start_at,'end_at',end_at,'timezone',tz,'staff',people,'hours',hours,'peaks',peaks,'avg_reaction',avg_reaction,'snapshot_at',clock_timestamp());
end $$;
revoke execute on function public.staff_analytics(uuid,text,date,date) from public,anon;
grant execute on function public.staff_analytics(uuid,text,date,date) to authenticated;

create function public.claim_push_batch() returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb; begin
 update push_deliveries d set done_at=clock_timestamp() from notifications n where d.notification_id=n.id and n.read_at is not null and d.done_at is null;
 update push_deliveries d set done_at=clock_timestamp() from notifications n join orders o on o.id=n.order_id
 where d.notification_id=n.id and d.done_at is null and n.kind in ('order','reminder','escalation','reassigned') and o.status<>'new';
 with candidates as (select d.notification_id,d.subscription_id from push_deliveries d
 where d.done_at is null and d.retry_at<=clock_timestamp() and (d.locked_until is null or d.locked_until<clock_timestamp()) and d.attempts<6
 order by d.retry_at limit 50 for update skip locked), claimed as (
 update push_deliveries d set locked_until=clock_timestamp()+interval '2 minutes',attempts=d.attempts+1
 from candidates c where d.notification_id=c.notification_id and d.subscription_id=c.subscription_id returning d.*)
 select coalesce(jsonb_agg(jsonb_build_object('notification_id',c.notification_id,'subscription_id',c.subscription_id,'attempts',c.attempts,
 'subscription',s.subscription,'message',n.message,'kind',n.kind,'order_id',n.order_id)),'[]') into result
 from claimed c join notifications n on n.id=c.notification_id join push_subscriptions s on s.id=c.subscription_id;
 return result; end $$;
create function public.finish_push(p_notification uuid,p_subscription uuid,p_success boolean,p_error text default null,p_gone boolean default false) returns void
language plpgsql security definer set search_path=public as $$ begin
 update push_deliveries set done_at=case when p_success or p_gone then clock_timestamp() else null end,
 locked_until=null,retry_at=clock_timestamp()+make_interval(secs=>least(3600,power(2,attempts)::int*30)),last_error=left(p_error,500)
 where notification_id=p_notification and subscription_id=p_subscription;
 if p_gone then delete from push_deliveries where subscription_id=p_subscription; delete from push_subscriptions where id=p_subscription; end if;
end $$;
revoke execute on function public.claim_push_batch(),public.finish_push(uuid,uuid,boolean,text,boolean) from public,anon,authenticated;
grant execute on function public.claim_push_batch(),public.finish_push(uuid,uuid,boolean,text,boolean) to service_role;
grant all on all tables in schema public to service_role;
grant usage,select on all sequences in schema public to service_role;
create function public.server_clock() returns timestamptz language sql as $$ select clock_timestamp() $$;
revoke execute on function public.server_clock() from public,anon;
grant execute on function public.server_clock() to authenticated;
create function public.find_staff_account(p_email text) returns uuid language sql security definer set search_path=public as $$
 select id from auth.users where lower(email)=lower(trim(p_email)) and (email_confirmed_at is not null or invited_at is not null) limit 1 $$;
revoke execute on function public.find_staff_account(text) from public,anon,authenticated;
grant execute on function public.find_staff_account(text) to service_role;
