import { createClient } from 'npm:@supabase/supabase-js@2';
const headers = { 'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? '', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
Deno.serve(async (req: Request) => {
 if (req.method === 'OPTIONS') return new Response('ok', { headers });
 const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...headers, 'Content-Type': 'application/json' } });
 if (req.method !== 'POST') return respond({ error: 'METHOD_NOT_ALLOWED' }, 405);
 try {
  const url = Deno.env.get('SUPABASE_URL')!;
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const token = req.headers.get('Authorization')?.replace(/^Bearer /, '') ?? '';
  const { data: { user }, error } = await admin.auth.getUser(token);
  if (error || !user) return respond({ error: 'AUTH_REQUIRED' }, 401);
  const body = await req.json();
  const { data: member } = await admin.from('restaurant_staff').select('role,active').eq('restaurant_id', body.restaurant_id).eq('user_id', user.id).single();
  const { data: rest } = await admin.from('restaurants').select('status').eq('id', body.restaurant_id).single();
  if (member?.role !== 'admin' || !member.active || rest?.status !== 'active') return respond({ error: 'FORBIDDEN' }, 403);
  if (!['admin', 'waiter'].includes(body.role) || typeof body.name !== 'string' || !body.name.trim() || body.name.length > 100 || typeof body.email !== 'string') return respond({ error: 'INVALID_STAFF' }, 400);
  if (typeof body.request_id !== 'string' || !/^[0-9a-f-]{36}$/i.test(body.request_id)) return respond({ error: 'INVALID_REQUEST' }, 400);
  const { data: existing, error: lookupError } = await admin.rpc('find_staff_account', { p_email: body.email });
  if (lookupError) throw lookupError;
  let userId = existing;
  if (!userId) {
   const { data, error: inviteError } = await admin.auth.admin.inviteUserByEmail(body.email, { redirectTo: Deno.env.get('APP_ORIGIN') });
   if (inviteError || !data.user) return respond({ error: inviteError?.message ?? 'INVITE_FAILED' }, 400);
   userId = data.user.id;
  }
  const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { error: saveError } = await caller.rpc('staff_command', { p_rest: body.restaurant_id, p_action: 'staff', p_key: body.request_id,
   p_data: { user_id: userId, name: body.name.trim(), role: body.role, active: true } });
  if (saveError) throw saveError;
  return respond({ user_id: userId, existing: Boolean(existing) });
 } catch { return respond({ error: 'INVITE_FAILED' }, 500); }
});
