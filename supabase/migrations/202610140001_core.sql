-- QR Waiter. All guest writes and staff commands run atomically on PostgreSQL.
revoke create on schema public from public,anon,authenticated;
create table public.super_admins(user_id uuid primary key references auth.users(id));
create table public.restaurants(id uuid primary key default gen_random_uuid(), name text not null,
 owner_id uuid not null references auth.users(id), status text not null default 'active' check(status in ('active','suspended')),
 plan text not null default 'mvp', created_at timestamptz not null default clock_timestamp());
create table public.restaurant_settings(restaurant_id uuid primary key references public.restaurants(id),
 timezone text not null default 'Europe/Kyiv', currency text not null default 'UAH',
 reminder_seconds int not null default 120 check(reminder_seconds>0),
 escalation_seconds int not null default 180 check(escalation_seconds>reminder_seconds));
create table public.restaurant_staff(restaurant_id uuid references public.restaurants(id), user_id uuid references auth.users(id),
 name text not null, role text not null check(role in ('admin','waiter')), active boolean not null default true,
 primary key(restaurant_id,user_id));
create table public.shifts(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 name text not null, started_at timestamptz not null default clock_timestamp(), ended_at timestamptz);
create unique index one_shift on public.shifts(restaurant_id) where ended_at is null;
create table public.dining_tables(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 name text not null, waiter_id uuid, state text not null default 'free' check(state in ('free','pending','serving','bill','cleanup')),
 unique(restaurant_id,name), unique(id,restaurant_id), foreign key(restaurant_id,waiter_id) references public.restaurant_staff(restaurant_id,user_id));
create table public.qr_codes(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 table_id uuid, waiter_id uuid, active boolean not null default true,
 check((table_id is null)<>(waiter_id is null)),
 foreign key(table_id,restaurant_id) references public.dining_tables(id,restaurant_id),
 foreign key(restaurant_id,waiter_id) references public.restaurant_staff(restaurant_id,user_id));
create unique index table_qr on public.qr_codes(table_id) where table_id is not null;
create unique index waiter_qr on public.qr_codes(restaurant_id,waiter_id) where waiter_id is not null;
create table public.menu_categories(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 name text not null, position int not null default 0, unique(id,restaurant_id), unique(restaurant_id,name));
create table public.menu_items(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 category_id uuid not null, name text not null, description text not null default '', photo_url text not null default '',
 portion text not null default '', price_minor int not null check(price_minor>=0), available boolean not null default true,
 unique(id,restaurant_id), foreign key(category_id,restaurant_id) references public.menu_categories(id,restaurant_id));
create table public.menu_item_options(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 item_id uuid not null, name text not null, price_minor int not null default 0 check(price_minor>=0), available boolean not null default true,
 foreign key(item_id,restaurant_id) references public.menu_items(id,restaurant_id));
create table public.table_sessions(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 table_id uuid not null, waiter_id uuid not null, opened_at timestamptz not null default clock_timestamp(), closed_at timestamptz,
 closed_by uuid references auth.users(id), close_reason text, bill_at timestamptz, prepared_at timestamptz, prepared_by uuid references auth.users(id),
 unique(id,restaurant_id), foreign key(table_id,restaurant_id) references public.dining_tables(id,restaurant_id),
 foreign key(restaurant_id,waiter_id) references public.restaurant_staff(restaurant_id,user_id));
create unique index one_open_session on public.table_sessions(table_id) where closed_at is null;
create table public.table_assignments(id bigint generated always as identity primary key, restaurant_id uuid not null references public.restaurants(id),
 table_id uuid not null, shift_id uuid references public.shifts(id), waiter_id uuid not null, assigned_at timestamptz not null default clock_timestamp(),
 ended_at timestamptz, assigned_by uuid references auth.users(id), foreign key(table_id,restaurant_id) references public.dining_tables(id,restaurant_id),
 foreign key(restaurant_id,waiter_id) references public.restaurant_staff(restaurant_id,user_id));
create unique index one_assignment on public.table_assignments(table_id) where ended_at is null;
create table public.presence_requests(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 table_id uuid not null, qr_id uuid not null references public.qr_codes(id), token_hash text not null unique, label text not null,
 created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null default clock_timestamp()+interval '5 minutes',
 approved_at timestamptz, approved_by uuid references auth.users(id), rejected_at timestamptz, session_id uuid,
 foreign key(table_id,restaurant_id) references public.dining_tables(id,restaurant_id),
 foreign key(session_id,restaurant_id) references public.table_sessions(id,restaurant_id));
create table public.guest_tokens(token_hash text primary key, restaurant_id uuid not null, session_id uuid not null,
 expires_at timestamptz not null default clock_timestamp()+interval '8 hours', revoked_at timestamptz,
 foreign key(session_id,restaurant_id) references public.table_sessions(id,restaurant_id));
create table public.orders(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null,
 session_id uuid not null, original_waiter_id uuid not null, waiter_id uuid not null, assignment_version int not null default 1,
 status text not null default 'new' check(status in ('new','accepted','preparing','ready','served','completed','cancelled')),
 created_at timestamptz not null default clock_timestamp(), accepted_at timestamptz, accepted_by uuid references auth.users(id),
 reaction_seconds numeric, cancelled_at timestamptz, cancellation_reason text, total_minor int not null check(total_minor>=0),
 comment text not null default '', reminder_at timestamptz not null, escalation_at timestamptz not null,
 overdue_at timestamptz, overdue_waiter_id uuid, unique(id,restaurant_id),
 foreign key(session_id,restaurant_id) references public.table_sessions(id,restaurant_id),
 foreign key(restaurant_id,original_waiter_id) references public.restaurant_staff(restaurant_id,user_id),
 foreign key(restaurant_id,waiter_id) references public.restaurant_staff(restaurant_id,user_id));
create index pending_order_deadlines on public.orders(escalation_at) where status='new';
create table public.order_items(id bigint generated always as identity primary key, restaurant_id uuid not null,
 order_id uuid not null, item_id uuid not null, name text not null, price_minor int not null check(price_minor>=0),
 quantity int not null check(quantity between 1 and 99), options jsonb not null default '[]',
 foreign key(order_id,restaurant_id) references public.orders(id,restaurant_id),
 foreign key(item_id,restaurant_id) references public.menu_items(id,restaurant_id));
create table public.order_status_history(id bigint generated always as identity primary key, restaurant_id uuid not null,
 order_id uuid not null, status text not null, at timestamptz not null default clock_timestamp(), actor_id uuid references auth.users(id),
 foreign key(order_id,restaurant_id) references public.orders(id,restaurant_id));
create table public.service_requests(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null,
 session_id uuid not null, waiter_id uuid not null, kind text not null check(kind in ('call','bill')),
 created_at timestamptz not null default clock_timestamp(), handled_at timestamptz, handled_by uuid references auth.users(id),
 foreign key(session_id,restaurant_id) references public.table_sessions(id,restaurant_id),
 foreign key(restaurant_id,waiter_id) references public.restaurant_staff(restaurant_id,user_id));
create unique index one_unhandled_request on public.service_requests(session_id,kind) where handled_at is null;
create table public.events(id bigint generated always as identity primary key, restaurant_id uuid not null references public.restaurants(id),
 session_id uuid, order_id uuid, kind text not null, at timestamptz not null default clock_timestamp(), actor_id uuid references auth.users(id),
 payload jsonb not null default '{}', foreign key(session_id,restaurant_id) references public.table_sessions(id,restaurant_id),
 foreign key(order_id,restaurant_id) references public.orders(id,restaurant_id));
create index event_period on public.events(restaurant_id,at,kind);
create index order_period on public.orders(restaurant_id,created_at);
create index order_acceptance on public.orders(restaurant_id,accepted_at,accepted_by);
create index order_assignment on public.orders(restaurant_id,waiter_id,status);
create index session_assignment on public.table_sessions(restaurant_id,waiter_id,closed_at);
create index table_assignment_read on public.dining_tables(restaurant_id,waiter_id);
create index menu_restaurant on public.menu_items(restaurant_id,category_id);
create index menu_options_item on public.menu_item_options(item_id);
create index request_waiter on public.service_requests(restaurant_id,waiter_id,handled_at);
create index presence_table on public.presence_requests(table_id,expires_at);
create table public.notification_jobs(id bigint generated always as identity primary key, order_id uuid not null references public.orders(id),
 kind text not null check(kind in ('reminder','escalation')), due_at timestamptz not null, done_at timestamptz, unique(order_id,kind));
create index due_jobs on public.notification_jobs(due_at) where done_at is null;
create table public.notifications(id uuid primary key default gen_random_uuid(), restaurant_id uuid not null references public.restaurants(id),
 recipient_id uuid not null references auth.users(id), order_id uuid, session_id uuid, kind text not null, message text not null,
 created_at timestamptz not null default clock_timestamp(), read_at timestamptz, dedupe_key text not null unique,
 foreign key(order_id,restaurant_id) references public.orders(id,restaurant_id), foreign key(session_id,restaurant_id) references public.table_sessions(id,restaurant_id));
create index notification_recipient on public.notifications(recipient_id,created_at desc);
create table public.idempotency_keys(actor text not null, key uuid not null, fingerprint text not null,
 result jsonb not null, created_at timestamptz not null default clock_timestamp(), primary key(actor,key));
create table public.rate_limits(key text primary key, attempts int not null, reset_at timestamptz not null);
create table public.push_subscriptions(id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 endpoint text not null unique, subscription jsonb not null, created_at timestamptz not null default clock_timestamp(),
 check(endpoint ~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com|[A-Za-z0-9-]+[.]notify[.]windows[.]com)/'),
 check(subscription->>'endpoint'=endpoint and subscription->'keys'->>'auth' is not null and subscription->'keys'->>'p256dh' is not null));
create table public.push_deliveries(notification_id uuid references public.notifications(id), subscription_id uuid references public.push_subscriptions(id) on delete cascade,
 attempts int not null default 0, retry_at timestamptz not null default clock_timestamp(), locked_until timestamptz, done_at timestamptz,
 last_error text, primary key(notification_id,subscription_id));

create function public.is_super() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from super_admins where user_id=auth.uid()) $$;
create function public.my_role(r uuid) returns text language sql stable security definer set search_path=public as $$
 select role from restaurant_staff where restaurant_id=r and user_id=auth.uid() and active $$;
create function public.token_hash(t text) returns text language sql immutable set search_path=public as $$
 select encode(sha256(convert_to(t,'UTF8')),'hex') $$;
create function public.audit(r uuid,s uuid,o uuid,k text,p jsonb default '{}') returns void
 language sql security definer set search_path=public as $$
 insert into events(restaurant_id,session_id,order_id,kind,actor_id,payload) values(r,s,o,k,auth.uid(),p) $$;
create function public.rate_limit(k text,max_attempts int,window_seconds int) returns void
 language plpgsql security definer set search_path=public as $$
 declare n int; begin
 insert into rate_limits values(k,1,clock_timestamp()+make_interval(secs=>window_seconds))
 on conflict(key) do update set attempts=case when rate_limits.reset_at<clock_timestamp() then 1 else rate_limits.attempts+1 end,
 reset_at=case when rate_limits.reset_at<clock_timestamp() then excluded.reset_at else rate_limits.reset_at end returning attempts into n;
 if n>max_attempts then raise exception 'RATE_LIMIT'; end if; end $$;
create function public.refresh_table(t uuid) returns void language plpgsql security definer set search_path=public as $$
 declare s table_sessions; begin select * into s from table_sessions where table_id=t and closed_at is null;
 if found then update dining_tables set state=case
 when exists(select 1 from orders where session_id=s.id and status='new') then 'pending'
 when s.bill_at is not null then 'bill' else 'serving' end where id=t; end if; end $$;
create function public.notify(r uuid,u uuid,o uuid,s uuid,k text,msg text,d text) returns void
 language plpgsql security definer set search_path=public as $$
 declare n uuid; begin
 insert into notifications(restaurant_id,recipient_id,order_id,session_id,kind,message,dedupe_key)
 values(r,u,o,s,k,msg,d) on conflict(dedupe_key) do nothing returning id into n;
 if n is not null then insert into push_deliveries(notification_id,subscription_id)
 select n,id from push_subscriptions where user_id=u on conflict do nothing; end if; end $$;
create function public.mark_overdue(oid uuid,now_at timestamptz) returns void
 language plpgsql security definer set search_path=public as $$
 declare o orders; begin
 update orders set overdue_at=escalation_at,overdue_waiter_id=waiter_id
 where id=oid and status='new' and overdue_at is null and escalation_at<=now_at returning * into o;
 if found then perform audit(o.restaurant_id,o.session_id,o.id,'overdue',jsonb_build_object('waiter_id',o.waiter_id,'deadline',o.escalation_at)); end if;
 end $$;
create function public.tick_waiting_orders() returns int language plpgsql security definer set search_path=public as $$
 declare j notification_jobs; o orders; a record; candidate record; locked_table uuid; locked_session uuid; count_done int:=0; n timestamptz:=clock_timestamp(); begin
 -- All commands acquire table -> session -> order -> job locks. Skip busy rows.
 for candidate in select id,session_id from orders where status='new' and exists(select 1 from notification_jobs where order_id=orders.id and done_at is null and due_at<=n) order by id loop
 select id into locked_table from dining_tables where id=(select table_id from table_sessions where id=candidate.session_id) for update skip locked;
 if not found then continue; end if;
 select id into locked_session from table_sessions where id=candidate.session_id and closed_at is null for update skip locked;
 if not found then continue; end if;
 select * into o from orders where id=candidate.id and status='new' for update skip locked;
 if not found then continue; end if;
 for j in select * from notification_jobs where order_id=o.id and done_at is null and due_at<=n order by due_at for update loop
 perform mark_overdue(o.id,n);
 if j.kind='reminder' then
 perform notify(o.restaurant_id,o.waiter_id,o.id,o.session_id,'reminder','Order awaiting confirmation',o.id||':reminder:'||o.waiter_id||':'||o.assignment_version);
 else
 for a in select user_id from restaurant_staff where restaurant_id=o.restaurant_id and active and role='admin' loop
 perform notify(o.restaurant_id,a.user_id,o.id,o.session_id,'escalation','Order escalated: confirmation overdue',o.id||':escalation:'||a.user_id);
 end loop; end if;
 perform audit(o.restaurant_id,o.session_id,o.id,j.kind); update notification_jobs set done_at=n where id=j.id; count_done:=count_done+1;
 end loop; end loop;
 update notification_jobs pending set done_at=n from orders settled where pending.order_id=settled.id and settled.status<>'new' and pending.done_at is null;
 return count_done; end $$;

create function public.create_restaurant(p_name text,p_staff_name text) returns uuid language plpgsql security definer set search_path=public as $$
 declare r uuid; begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if length(trim(p_name)) not between 1 and 120 or length(trim(p_staff_name)) not between 1 and 100 then raise exception 'INVALID_NAME'; end if;
 perform rate_limit(auth.uid()||':restaurant',5,3600);
 insert into restaurants(name,owner_id) values(trim(p_name),auth.uid()) returning id into r;
 insert into restaurant_settings(restaurant_id) values(r);
 insert into restaurant_staff values(r,auth.uid(),trim(p_staff_name),'admin',true);
 perform audit(r,null,null,'restaurant_created'); return r; end $$;

create function public.public_menu(p_qr uuid) returns jsonb language plpgsql security definer set search_path=public as $$
 declare q qr_codes; begin select * into q from qr_codes where id=p_qr and active;
 if not found or not exists(select 1 from restaurants where id=q.restaurant_id and status='active') then raise exception 'QR_INACTIVE'; end if;
 return jsonb_build_object('restaurant',(select jsonb_build_object('id',r.id,'name',r.name,'currency',s.currency) from restaurants r join restaurant_settings s on s.restaurant_id=r.id where r.id=q.restaurant_id),
 'tables',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)),'[]') from dining_tables where restaurant_id=q.restaurant_id and (id=q.table_id or (q.waiter_id is not null and waiter_id=q.waiter_id))),
 'categories',(select coalesce(jsonb_agg(to_jsonb(c) order by position,name),'[]') from menu_categories c where restaurant_id=q.restaurant_id),
 'items',(select coalesce(jsonb_agg(to_jsonb(i) order by name),'[]') from menu_items i where restaurant_id=q.restaurant_id),
 'options',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from menu_item_options x where restaurant_id=q.restaurant_id)); end $$;
create function public.request_presence(p_qr uuid,p_table uuid,p_label text) returns jsonb language plpgsql security definer set search_path=public as $$
 declare q qr_codes; t dining_tables; token text:=gen_random_uuid()::text||gen_random_uuid()::text; rid uuid; begin
 select * into q from qr_codes where id=p_qr and active;
 if not found or not exists(select 1 from restaurants where id=q.restaurant_id and status='active') then raise exception 'QR_INACTIVE'; end if;
 select * into t from dining_tables where id=p_table and restaurant_id=q.restaurant_id for update;
 if not found or not (t.id=q.table_id or (q.waiter_id is not null and t.waiter_id=q.waiter_id)) then raise exception 'TABLE_MISMATCH'; end if;
 if t.waiter_id is null or not exists(select 1 from restaurant_staff where restaurant_id=q.restaurant_id and user_id=t.waiter_id and active) then raise exception 'NO_WAITER'; end if;
 if t.state='cleanup' then raise exception 'TABLE_NOT_READY'; end if;
 if length(trim(p_label)) not between 1 and 60 then raise exception 'INVALID_NAME'; end if;
 -- A table-wide cap is a secondary guard. Edge gateway adds per-IP limits.
 perform rate_limit(p_table||':presence',30,300);
 insert into presence_requests(restaurant_id,table_id,qr_id,token_hash,label) values(q.restaurant_id,t.id,q.id,token_hash(token),trim(p_label)) returning id into rid;
 perform notify(q.restaurant_id,t.waiter_id,null,null,'presence',trim(p_label)||' asks to join '||t.name,rid||':presence');
 return jsonb_build_object('token',token,'request_id',rid,'status','pending'); end $$;

create function public.guest_state(p_token text) returns jsonb language plpgsql security definer set search_path=public as $$
 declare p presence_requests; g guest_tokens; s table_sessions; begin
 if length(p_token)>100 then raise exception 'SESSION_INVALID'; end if;
 select * into p from presence_requests where token_hash=token_hash(p_token);
 if not found then raise exception 'SESSION_INVALID'; end if;
 if p.rejected_at is not null then return jsonb_build_object('status','rejected'); end if;
 if p.approved_at is null then
 if p.expires_at<=clock_timestamp() then return jsonb_build_object('status','expired'); end if;
 return jsonb_build_object('status','pending','label',p.label); end if;
 select * into g from guest_tokens where token_hash=p.token_hash;
 select * into s from table_sessions where id=g.session_id;
 if g.token_hash is null or g.revoked_at is not null or g.expires_at<=clock_timestamp() or s.closed_at is not null
 or not exists(select 1 from restaurants where id=s.restaurant_id and status='active') then return jsonb_build_object('status','closed'); end if;
 return jsonb_build_object('status','active','session',to_jsonb(s),'server_now',clock_timestamp(),
 'orders',(select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(i)),'[]') from order_items i where order_id=o.id)) order by o.created_at),'[]') from orders o where session_id=s.id),
 'requests',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from service_requests x where session_id=s.id)); end $$;

create function public.guest_command(p_token text,p_action text,p_data jsonb,p_key uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
<<guest_cmd>>
 declare g guest_tokens; s table_sessions; settings restaurant_settings; o uuid; x jsonb; item menu_items; opt menu_item_options;
 qty int; price int; total bigint:=0; options jsonb; optid text; result jsonb; old idempotency_keys;
 fp text:=token_hash(p_action||p_data::text); actor text:='guest:'||token_hash(p_token); req uuid; locked_table uuid; begin
 if p_key is null or length(p_token)>100 then raise exception 'INVALID_REQUEST'; end if;
 select * into g from guest_tokens where token_hash=token_hash(p_token);
 if not found or g.revoked_at is not null or g.expires_at<=clock_timestamp() then raise exception 'SESSION_INVALID'; end if;
 select id into locked_table from dining_tables where id=(select table_id from table_sessions where id=g.session_id) for update;
 select * into s from table_sessions where id=g.session_id for update;
 if g.expires_at<=clock_timestamp() then raise exception 'SESSION_INVALID'; end if;
 if s.closed_at is not null or not exists(select 1 from restaurants where id=s.restaurant_id and status='active') then raise exception 'SESSION_CLOSED'; end if;
 select * into old from idempotency_keys where actor=guest_cmd.actor and key=p_key;
 if found then if old.fingerprint<>fp then raise exception 'IDEMPOTENCY_CONFLICT'; end if; return old.result; end if;
 perform rate_limit(actor||':write',60,60);
 if p_action='order' then
 if jsonb_typeof(coalesce(p_data->'items','null'))<>'array' or jsonb_array_length(p_data->'items') not between 1 and 100 then raise exception 'INVALID_ITEMS'; end if;
 if length(coalesce(p_data->>'comment',''))>1000 then raise exception 'INVALID_COMMENT'; end if;
 select * into settings from restaurant_settings where restaurant_id=s.restaurant_id;
 insert into orders(restaurant_id,session_id,original_waiter_id,waiter_id,total_minor,comment,reminder_at,escalation_at)
 values(s.restaurant_id,s.id,s.waiter_id,s.waiter_id,0,coalesce(p_data->>'comment',''),clock_timestamp()+make_interval(secs=>settings.reminder_seconds),clock_timestamp()+make_interval(secs=>settings.escalation_seconds)) returning id into o;
 for x in select value from jsonb_array_elements(p_data->'items') loop
 qty:=(x->>'quantity')::int; if qty is null or qty not between 1 and 99 then raise exception 'INVALID_QUANTITY'; end if;
 select * into item from menu_items where id=(x->>'id')::uuid and restaurant_id=s.restaurant_id and available for share;
 if not found then raise exception 'ITEM_UNAVAILABLE'; end if;
 price:=item.price_minor; options:='[]';
 if jsonb_typeof(coalesce(x->'options','[]'))<>'array' then raise exception 'INVALID_OPTIONS'; end if;
 if (select count(*)<>count(distinct value) from jsonb_array_elements_text(coalesce(x->'options','[]'))) then raise exception 'DUPLICATE_OPTIONS'; end if;
 for optid in select value from jsonb_array_elements_text(coalesce(x->'options','[]')) loop
 select * into opt from menu_item_options where id=optid::uuid and item_id=item.id and restaurant_id=s.restaurant_id and available for share;
 if not found then raise exception 'OPTION_UNAVAILABLE'; end if;
 price:=price+opt.price_minor; options:=options||jsonb_build_array(jsonb_build_object('id',opt.id,'name',opt.name,'price_minor',opt.price_minor)); end loop;
 if x->>'expected_price_minor' is null or (x->>'expected_price_minor')::int<>price then raise exception 'PRICE_CHANGED'; end if;
 total:=total+price::bigint*qty; if total>2147483647 then raise exception 'ORDER_TOO_LARGE'; end if;
 insert into order_items(restaurant_id,order_id,item_id,name,price_minor,quantity,options) values(s.restaurant_id,o,item.id,item.name,price,qty,options);
 end loop;
 update orders set total_minor=total where id=o;
 update table_sessions set bill_at=null where id=s.id;
 update service_requests set handled_at=clock_timestamp(),handled_by=null where session_id=s.id and kind='bill' and handled_at is null;
 insert into order_status_history(restaurant_id,order_id,status) values(s.restaurant_id,o,'new');
 perform audit(s.restaurant_id,s.id,o,'order_created',jsonb_build_object('waiter_id',s.waiter_id,'total_minor',total));
 perform audit(s.restaurant_id,s.id,o,'order_received',jsonb_build_object('waiter_id',s.waiter_id));
 insert into notification_jobs(order_id,kind,due_at) select id,'reminder',reminder_at from orders where id=o;
 insert into notification_jobs(order_id,kind,due_at) select id,'escalation',escalation_at from orders where id=o;
 perform notify(s.restaurant_id,s.waiter_id,o,s.id,'order','New order',o||':created');
 perform refresh_table(s.table_id); result:=jsonb_build_object('order_id',o);
 elsif p_action in ('call','bill') then
 insert into service_requests(restaurant_id,session_id,waiter_id,kind) values(s.restaurant_id,s.id,s.waiter_id,p_action)
 on conflict(session_id,kind) where handled_at is null do update set kind=excluded.kind returning id into req;
 if p_action='bill' then update table_sessions set bill_at=clock_timestamp() where id=s.id; perform refresh_table(s.table_id); end if;
 perform notify(s.restaurant_id,s.waiter_id,null,s.id,p_action,'Guest request: '||p_action,req||':'||p_action);
 if not exists(select 1 from events where session_id=s.id and kind='request_created' and payload->>'request_id'=req::text) then
 perform audit(s.restaurant_id,s.id,null,'request_created',jsonb_build_object('request_id',req,'kind',p_action,'waiter_id',s.waiter_id)); end if;
 result:=jsonb_build_object('request_id',req);
 else raise exception 'UNKNOWN_ACTION'; end if;
 insert into idempotency_keys values(actor,p_key,fp,result,clock_timestamp()); return result;
 end $$;

create function public.staff_command(p_rest uuid,p_action text,p_data jsonb,p_key uuid) returns jsonb
 language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
<<cmd>>
 declare role text:=my_role(p_rest); uid uuid:=auth.uid(); id uuid; target uuid; t dining_tables; s table_sessions; o orders;
 p presence_requests; rec record; result jsonb:='{}'; old idempotency_keys; actor text:='staff:'||auth.uid()||':'||p_rest;
 fp text:=token_hash(p_action||p_data::text); n timestamptz:=clock_timestamp(); newstatus text; shift uuid;
 begin
 if role is null or p_key is null then raise exception 'FORBIDDEN'; end if;
 if not exists(select 1 from restaurants where restaurants.id=p_rest and status='active') then raise exception 'RESTAURANT_SUSPENDED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor,0));
 select * into old from idempotency_keys where idempotency_keys.actor=cmd.actor and key=p_key;
 if found then if old.fingerprint<>fp then raise exception 'IDEMPOTENCY_CONFLICT'; end if; return old.result; end if;
 if p_action in ('settings','category','item','option','table','assign','qr','staff','shift_start','shift_end') and role<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
 case p_action
 when 'settings' then
 if not exists(select 1 from pg_timezone_names where name=p_data->>'timezone') then raise exception 'INVALID_TIMEZONE'; end if;
 if (p_data->>'currency')!~'^[A-Z]{3}$' then raise exception 'INVALID_CURRENCY'; end if;
 if exists(select 1 from orders where restaurant_id=p_rest) and (select currency from restaurant_settings where restaurant_id=p_rest)<>p_data->>'currency' then raise exception 'CURRENCY_LOCKED'; end if;
 update restaurant_settings set timezone=p_data->>'timezone',currency=p_data->>'currency',reminder_seconds=(p_data->>'reminder_seconds')::int,
 escalation_seconds=(p_data->>'escalation_seconds')::int where restaurant_id=p_rest;
 perform audit(p_rest,null,null,'settings_changed',p_data);
 when 'category' then
 id:=coalesce((p_data->>'id')::uuid,gen_random_uuid());
 if length(trim(p_data->>'name')) not between 1 and 100 then raise exception 'INVALID_NAME'; end if;
 if exists(select 1 from menu_categories where menu_categories.id=cmd.id and restaurant_id<>p_rest) then raise exception 'FORBIDDEN'; end if;
 insert into menu_categories values(id,p_rest,trim(p_data->>'name'),coalesce((p_data->>'position')::int,0)) on conflict(id) do update set name=excluded.name,position=excluded.position;
 result:=jsonb_build_object('id',id);
 when 'item' then
 id:=coalesce((p_data->>'id')::uuid,gen_random_uuid());
 if length(trim(p_data->>'name')) not between 1 and 120 or length(coalesce(p_data->>'description',''))>2000 then raise exception 'INVALID_NAME'; end if;
 if coalesce(p_data->>'photo_url','')<>'' and (p_data->>'photo_url')!~'^https://' then raise exception 'INVALID_PHOTO'; end if;
 if exists(select 1 from menu_items where menu_items.id=cmd.id and restaurant_id<>p_rest) then raise exception 'FORBIDDEN'; end if;
 insert into menu_items values(id,p_rest,(p_data->>'category_id')::uuid,p_data->>'name',coalesce(p_data->>'description',''),coalesce(p_data->>'photo_url',''),
 coalesce(p_data->>'portion',''),(p_data->>'price_minor')::int,coalesce((p_data->>'available')::boolean,true))
 on conflict(id) do update set category_id=excluded.category_id,name=excluded.name,description=excluded.description,photo_url=excluded.photo_url,portion=excluded.portion,price_minor=excluded.price_minor,available=excluded.available;
 result:=jsonb_build_object('id',id);
 when 'option' then
 id:=coalesce((p_data->>'id')::uuid,gen_random_uuid());
 if length(trim(p_data->>'name')) not between 1 and 100 then raise exception 'INVALID_NAME'; end if;
 if exists(select 1 from menu_item_options where menu_item_options.id=cmd.id and restaurant_id<>p_rest) then raise exception 'FORBIDDEN'; end if;
 insert into menu_item_options values(id,p_rest,(p_data->>'item_id')::uuid,p_data->>'name',(p_data->>'price_minor')::int,coalesce((p_data->>'available')::boolean,true))
 on conflict(id) do update set name=excluded.name,price_minor=excluded.price_minor,available=excluded.available;
 result:=jsonb_build_object('id',id);
 when 'staff' then
 target:=(p_data->>'user_id')::uuid;
 perform 1 from restaurant_staff where restaurant_id=p_rest and user_id=target for update;
 if p_data->>'role' not in ('admin','waiter') or length(trim(p_data->>'name')) not between 1 and 100 then raise exception 'INVALID_STAFF'; end if;
 if target=uid and (p_data->>'role'<>'admin' or not coalesce((p_data->>'active')::boolean,true)) then raise exception 'KEEP_OWN_ADMIN'; end if;
 if target=(select owner_id from restaurants where restaurants.id=p_rest) and (p_data->>'role'<>'admin' or not coalesce((p_data->>'active')::boolean,true)) then raise exception 'OWNER_MUST_BE_ADMIN'; end if;
 if not coalesce((p_data->>'active')::boolean,true) and exists(select 1 from dining_tables where restaurant_id=p_rest and waiter_id=target) then raise exception 'REASSIGN_FIRST'; end if;
 insert into restaurant_staff values(p_rest,target,p_data->>'name',p_data->>'role',coalesce((p_data->>'active')::boolean,true))
 on conflict(restaurant_id,user_id) do update set name=excluded.name,role=excluded.role,active=excluded.active;
 insert into qr_codes(restaurant_id,waiter_id) values(p_rest,target) on conflict do nothing;
 perform audit(p_rest,null,null,'staff_changed',p_data-'email');
 when 'table' then
 id:=gen_random_uuid(); target:=(p_data->>'waiter_id')::uuid;
 if length(trim(p_data->>'name')) not between 1 and 60 then raise exception 'INVALID_NAME'; end if;
 perform 1 from restaurant_staff where restaurant_id=p_rest and user_id=target and active for share;
 if not found then raise exception 'NO_WAITER'; end if;
 insert into dining_tables(id,restaurant_id,name,waiter_id) values(id,p_rest,p_data->>'name',target);
 insert into qr_codes(restaurant_id,table_id) values(p_rest,id);
 select shifts.id into shift from shifts where restaurant_id=p_rest and ended_at is null;
 insert into table_assignments(restaurant_id,table_id,shift_id,waiter_id,assigned_by) values(p_rest,id,shift,target,uid);
 result:=jsonb_build_object('id',id);
 when 'assign' then
 target:=(p_data->>'waiter_id')::uuid;
 select * into t from dining_tables where dining_tables.id=(p_data->>'table_id')::uuid and restaurant_id=p_rest for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 perform 1 from restaurant_staff where restaurant_id=p_rest and user_id=target and active for share;
 if not found then raise exception 'NO_WAITER'; end if;
 select * into s from table_sessions where table_id=t.id and closed_at is null for update;
 n:=clock_timestamp();
 for o in select * from orders where session_id=s.id and status not in ('completed','cancelled') order by orders.id for update loop
 perform mark_overdue(o.id,n);
 update orders set waiter_id=target,assignment_version=assignment_version+1 where orders.id=o.id;
 perform audit(p_rest,s.id,o.id,'order_received',jsonb_build_object('waiter_id',target,'previous_waiter_id',o.waiter_id));
 if o.status='new' then perform notify(p_rest,target,o.id,s.id,'reassigned','Order reassigned',o.id||':assigned:'||(o.assignment_version+1)); end if;
 end loop;
 update dining_tables set waiter_id=target where dining_tables.id=t.id;
 update table_sessions set waiter_id=target where table_sessions.id=s.id;
 for rec in select * from service_requests where session_id=s.id and handled_at is null loop
 update service_requests set waiter_id=target where service_requests.id=rec.id;
 perform notify(p_rest,target,null,s.id,rec.kind,'Guest request reassigned',rec.id||':assigned:'||target);
 end loop;
 update table_assignments set ended_at=n where table_id=t.id and ended_at is null;
 select shifts.id into shift from shifts where restaurant_id=p_rest and ended_at is null;
 insert into table_assignments(restaurant_id,table_id,shift_id,waiter_id,assigned_by) values(p_rest,t.id,shift,target,uid);
 perform audit(p_rest,s.id,null,'table_assigned',jsonb_build_object('table_id',t.id,'waiter_id',target,'previous_waiter_id',t.waiter_id));
 when 'qr' then
 update qr_codes set active=(p_data->>'active')::boolean where qr_codes.id=(p_data->>'id')::uuid and restaurant_id=p_rest;
 if not found then raise exception 'NOT_FOUND'; end if;
 perform audit(p_rest,null,null,'qr_changed',p_data);
 when 'shift_start' then
 insert into shifts(restaurant_id,name) values(p_rest,coalesce(nullif(trim(p_data->>'name'),''),'Shift')) returning shifts.id into shift;
 update table_assignments set ended_at=n where restaurant_id=p_rest and ended_at is null;
 insert into table_assignments(restaurant_id,table_id,shift_id,waiter_id,assigned_by)
 select p_rest,dining_tables.id,shift,waiter_id,uid from dining_tables where restaurant_id=p_rest and waiter_id is not null;
 perform audit(p_rest,null,null,'shift_started',jsonb_build_object('shift_id',shift)); result:=jsonb_build_object('id',shift);
 when 'shift_end' then
 update shifts set ended_at=n where restaurant_id=p_rest and ended_at is null returning shifts.id into shift;
 if shift is null then raise exception 'NO_SHIFT'; end if;
 update table_assignments set ended_at=n where restaurant_id=p_rest and shift_id=shift and ended_at is null;
 perform audit(p_rest,null,null,'shift_ended',jsonb_build_object('shift_id',shift));
 when 'presence' then
 select * into p from presence_requests where presence_requests.id=(p_data->>'id')::uuid and restaurant_id=p_rest for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 select * into t from dining_tables where dining_tables.id=p.table_id for update;
 n:=clock_timestamp();
 if role<>'admin' and t.waiter_id<>uid then raise exception 'FORBIDDEN'; end if;
 if p.approved_at is not null then result:=jsonb_build_object('session_id',p.session_id);
 elsif p.expires_at<=n or p.rejected_at is not null then raise exception 'PRESENCE_EXPIRED';
 elsif not coalesce((p_data->>'approve')::boolean,false) then
 update presence_requests set rejected_at=n where presence_requests.id=p.id; perform audit(p_rest,null,null,'presence_rejected',jsonb_build_object('request_id',p.id));
 else
 if not exists(select 1 from qr_codes where qr_codes.id=p.qr_id and active) or t.state='cleanup' then raise exception 'TABLE_NOT_READY'; end if;
 select * into s from table_sessions where table_id=t.id and closed_at is null for update;
 if not found then insert into table_sessions(restaurant_id,table_id,waiter_id) values(p_rest,t.id,t.waiter_id) returning * into s;
 perform audit(p_rest,s.id,null,'session_opened',jsonb_build_object('waiter_id',t.waiter_id)); end if;
 insert into guest_tokens(token_hash,restaurant_id,session_id) values(p.token_hash,p_rest,s.id);
 update presence_requests set approved_at=n,approved_by=uid,session_id=s.id where presence_requests.id=p.id;
 perform audit(p_rest,s.id,null,'presence_approved',jsonb_build_object('request_id',p.id)); perform refresh_table(t.id);
 result:=jsonb_build_object('session_id',s.id); end if;
 when 'order_status' then
 select * into t from dining_tables where dining_tables.id=(select table_id from table_sessions where table_sessions.id=(select session_id from orders where orders.id=(p_data->>'id')::uuid and restaurant_id=p_rest)) for update;
 select * into s from table_sessions where table_sessions.id=(select session_id from orders where orders.id=(p_data->>'id')::uuid and restaurant_id=p_rest) for update;
 select * into o from orders where orders.id=(p_data->>'id')::uuid and restaurant_id=p_rest for update;
 n:=clock_timestamp();
 if not found or s.closed_at is not null then raise exception 'NOT_FOUND'; end if;
 if role<>'admin' and o.waiter_id<>uid then raise exception 'FORBIDDEN'; end if;
 newstatus:=p_data->>'status';
 if newstatus=o.status then result:=jsonb_build_object('id',o.id,'status',o.status);
 else
 if not ((o.status='new' and newstatus='accepted') or (o.status='accepted' and newstatus='preparing') or
 (o.status='preparing' and newstatus='ready') or (o.status='ready' and newstatus='served') or
 (o.status='served' and newstatus='completed') or (o.status not in ('completed','cancelled') and newstatus='cancelled')) then raise exception 'INVALID_TRANSITION'; end if;
 perform mark_overdue(o.id,n);
 if newstatus='accepted' then update orders set accepted_at=n,accepted_by=uid,reaction_seconds=extract(epoch from n-created_at) where orders.id=o.id;
 elsif newstatus='cancelled' then
 if length(trim(coalesce(p_data->>'reason',''))) not between 1 and 500 then raise exception 'REASON_REQUIRED'; end if;
 update orders set cancelled_at=n,cancellation_reason=p_data->>'reason' where orders.id=o.id; end if;
 update orders set status=newstatus where orders.id=o.id;
 insert into order_status_history(restaurant_id,order_id,status,actor_id) values(p_rest,o.id,newstatus,uid);
 perform audit(p_rest,s.id,o.id,'order_status',jsonb_build_object('status',newstatus,'waiter_id',o.waiter_id,'reason',p_data->>'reason'));
 update notification_jobs set done_at=n where order_id=o.id and done_at is null; perform refresh_table(s.table_id);
 result:=jsonb_build_object('id',o.id,'status',newstatus); end if;
 when 'request_handled' then
 select * into rec from service_requests where service_requests.id=(p_data->>'id')::uuid and restaurant_id=p_rest for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if role<>'admin' and rec.waiter_id<>uid then raise exception 'FORBIDDEN'; end if;
 update service_requests set handled_at=coalesce(handled_at,n),handled_by=coalesce(handled_by,uid) where service_requests.id=rec.id;
 perform audit(p_rest,rec.session_id,null,'request_handled',jsonb_build_object('request_id',rec.id));
 when 'close_session','table_state' then
 if p_action='table_state' and role<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
 select * into t from dining_tables where dining_tables.id=(p_data->>'table_id')::uuid and restaurant_id=p_rest for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if role<>'admin' and t.waiter_id<>uid then raise exception 'FORBIDDEN'; end if;
 select * into s from table_sessions where table_id=t.id and closed_at is null for update;
 n:=clock_timestamp();
 newstatus:=case when p_action='close_session' then 'cleanup' else p_data->>'state' end;
 if newstatus in ('cleanup','free') and s.id is not null then
 if exists(select 1 from orders where session_id=s.id and status not in ('completed','cancelled')) then
 if role<>'admin' or length(trim(coalesce(p_data->>'reason','')))=0 then raise exception 'UNFINISHED_ORDERS'; end if;
 for o in select * from orders where session_id=s.id and status not in ('completed','cancelled') order by orders.id for update loop
 perform mark_overdue(o.id,n); update orders set status='cancelled',cancelled_at=n,cancellation_reason=p_data->>'reason' where orders.id=o.id;
 insert into order_status_history(restaurant_id,order_id,status,actor_id) values(p_rest,o.id,'cancelled',uid);
 perform audit(p_rest,s.id,o.id,'order_status',jsonb_build_object('status','cancelled','waiter_id',o.waiter_id,'reason',p_data->>'reason'));
 update notification_jobs set done_at=n where order_id=o.id and done_at is null; end loop; end if;
 n:=clock_timestamp();
 update table_sessions set closed_at=n,closed_by=uid,close_reason=p_data->>'reason' where table_sessions.id=s.id;
 update guest_tokens set revoked_at=n where session_id=s.id;
 update presence_requests set rejected_at=n where table_id=t.id and approved_at is null and rejected_at is null;
 update service_requests set handled_at=n,handled_by=uid where session_id=s.id and handled_at is null;
 perform audit(p_rest,s.id,null,'session_closed',jsonb_build_object('reason',p_data->>'reason'));
 elsif newstatus not in ('cleanup','free') then
 if s.id is null then raise exception 'SESSION_REQUIRED'; end if;
 if newstatus='pending' and not exists(select 1 from orders where session_id=s.id and status='new') then raise exception 'NO_PENDING_ORDERS'; end if;
 if newstatus='serving' and exists(select 1 from orders where session_id=s.id and status='new') then raise exception 'PENDING_ORDERS'; end if;
 if newstatus='bill' then update table_sessions set bill_at=n where table_sessions.id=s.id;
 elsif newstatus='serving' then update table_sessions set bill_at=null where table_sessions.id=s.id; end if;
 end if;
 update dining_tables set state=newstatus where dining_tables.id=t.id;
 if newstatus='free' then update table_sessions set prepared_at=n,prepared_by=uid where table_id=t.id and closed_at is not null and prepared_at is null; end if;
 perform audit(p_rest,s.id,null,'table_state',jsonb_build_object('table_id',t.id,'state',newstatus,'reason',p_data->>'reason'));
 when 'prepared' then
 update dining_tables set state='free' where dining_tables.id=(p_data->>'table_id')::uuid and restaurant_id=p_rest and state='cleanup'
 and (role='admin' or waiter_id=uid) returning * into t;
 if not found then raise exception 'TABLE_NOT_READY'; end if;
 update table_sessions set prepared_at=n,prepared_by=uid where table_id=t.id and closed_at is not null and prepared_at is null;
 perform audit(p_rest,null,null,'table_prepared',jsonb_build_object('table_id',t.id));
 when 'notification_read' then
 update notifications set read_at=n where notifications.id=(p_data->>'id')::uuid and restaurant_id=p_rest and recipient_id=uid;
 else raise exception 'UNKNOWN_ACTION'; end case;
 insert into idempotency_keys values(actor,p_key,fp,result,n); return result;
 end $$;

create function public.super_command(p_action text,p_data jsonb) returns void language plpgsql security definer set search_path=public as $$
 declare r uuid:=(p_data->>'id')::uuid; begin if not is_super() then raise exception 'FORBIDDEN'; end if;
 if p_action='restaurant' then update restaurants set status=p_data->>'status',plan=p_data->>'plan' where id=r;
 elsif p_action='owner' then
 if not exists(select 1 from restaurant_staff where restaurant_id=r and user_id=(p_data->>'owner_id')::uuid and active and role='admin') then raise exception 'OWNER_MUST_BE_ADMIN'; end if;
 update restaurants set owner_id=(p_data->>'owner_id')::uuid where id=r;
 else raise exception 'UNKNOWN_ACTION'; end if;
 if not found then raise exception 'NOT_FOUND'; end if; perform audit(r,null,null,'super_admin_change',p_data); end $$;

-- Immutable evidence. No API role can rewrite history.
create function public.prevent_history_change() returns trigger language plpgsql as $$ begin raise exception 'IMMUTABLE_HISTORY'; end $$;
create trigger immutable_events before update or delete on public.events for each row execute function public.prevent_history_change();
create trigger immutable_order_history before update or delete on public.order_status_history for each row execute function public.prevent_history_change();

-- Enable RLS everywhere, including server-only tables. No anonymous table access.
do $$ declare n text; begin foreach n in array array['super_admins','restaurants','restaurant_settings','restaurant_staff','shifts','dining_tables','qr_codes','menu_categories','menu_items','menu_item_options','table_sessions','table_assignments','presence_requests','guest_tokens','orders','order_items','order_status_history','service_requests','events','notification_jobs','notifications','idempotency_keys','rate_limits','push_subscriptions','push_deliveries'] loop
 execute format('alter table public.%I enable row level security',n);
 execute format('revoke all on public.%I from anon,authenticated',n); end loop; end $$;
create policy self_super on public.super_admins for select to authenticated using(user_id=auth.uid());
create policy restaurant_read on public.restaurants for select to authenticated using(my_role(id) is not null or is_super());
create policy staff_read on public.restaurant_staff for select to authenticated using(my_role(restaurant_id) is not null or is_super());
do $$ declare n text; begin foreach n in array array['restaurant_settings','shifts','qr_codes','menu_categories','menu_items','menu_item_options','table_assignments'] loop
 execute format('create policy member_read on public.%I for select to authenticated using(public.my_role(restaurant_id) is not null)',n); end loop; end $$;
create policy table_read on public.dining_tables for select to authenticated using(my_role(restaurant_id)='admin' or (my_role(restaurant_id) is not null and waiter_id=auth.uid()));
create policy session_read on public.table_sessions for select to authenticated using(my_role(restaurant_id)='admin' or (my_role(restaurant_id) is not null and (waiter_id=auth.uid() or closed_by=auth.uid())));
create policy order_read on public.orders for select to authenticated using(my_role(restaurant_id)='admin' or (my_role(restaurant_id) is not null and (waiter_id=auth.uid() or accepted_by=auth.uid())));
create policy request_read on public.service_requests for select to authenticated using(my_role(restaurant_id)='admin' or (my_role(restaurant_id) is not null and waiter_id=auth.uid()));
create policy presence_read on public.presence_requests for select to authenticated using(my_role(restaurant_id)='admin' or exists(select 1 from dining_tables where id=table_id and waiter_id=auth.uid() and my_role(restaurant_id) is not null));
create policy event_read on public.events for select to authenticated using(my_role(restaurant_id)='admin' or (my_role(restaurant_id) is not null and (actor_id=auth.uid() or payload->>'waiter_id'=auth.uid()::text or exists(select 1 from table_sessions where id=session_id and (waiter_id=auth.uid() or closed_by=auth.uid())))));
create policy item_read on public.order_items for select to authenticated using(exists(select 1 from orders where id=order_id));
create policy history_read on public.order_status_history for select to authenticated using(exists(select 1 from orders where id=order_id));
create policy notification_read on public.notifications for select to authenticated using(recipient_id=auth.uid() and my_role(restaurant_id) is not null);
create policy subscription_own on public.push_subscriptions for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
grant select on public.super_admins,public.restaurants,public.restaurant_settings,public.restaurant_staff,public.shifts,public.dining_tables,public.qr_codes,public.menu_categories,public.menu_items,public.menu_item_options,public.table_sessions,public.table_assignments,public.orders,public.order_items,public.order_status_history,public.service_requests,public.events,public.notifications to authenticated;
-- Presence tokens/hashes are never returned to staff clients.
grant select(id,restaurant_id,table_id,label,created_at,expires_at,approved_at,rejected_at,session_id) on public.presence_requests to authenticated;
grant select,insert,update,delete on public.push_subscriptions to authenticated;
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.is_super(),public.my_role(uuid) to authenticated;
grant execute on function public.create_restaurant(text,text),public.staff_command(uuid,text,jsonb,uuid),public.super_command(text,jsonb) to authenticated;
grant execute on function public.public_menu(uuid),public.request_presence(uuid,uuid,text),public.guest_state(text),public.guest_command(text,text,jsonb,uuid) to anon,authenticated;
grant execute on function public.tick_waiting_orders() to service_role;
