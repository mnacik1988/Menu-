import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
Deno.serve(async (req: Request) => {
 const dispatchSecret=Deno.env.get('PUSH_DISPATCH_SECRET');
 if (!dispatchSecret || req.method!=='POST' || req.headers.get('Authorization') !== `Bearer ${dispatchSecret}`) return new Response('Unauthorized', { status: 401 });
 const publicKey = Deno.env.get('VAPID_PUBLIC_KEY'), privateKey = Deno.env.get('VAPID_PRIVATE_KEY'), subject = Deno.env.get('VAPID_SUBJECT');
 if (!publicKey || !privateKey || !subject) return new Response('VAPID not configured', { status: 503 });
 webpush.setVapidDetails(subject, publicKey, privateKey);
 const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
 const { data: batch, error } = await db.rpc('claim_push_batch');
 if (error) return new Response('Queue unavailable', { status: 503 });
 for (const job of batch ?? []) {
  try {
   const messages:Record<string,Record<string,string>>={uk:{order:'Нове замовлення',reminder:'Замовлення очікує підтвердження',escalation:'Підтвердження прострочено',presence:'Гість очікує підтвердження присутності',call:'Виклик офіціанта',bill:'Запит рахунку',reassigned:'Столик переназначено'},ru:{order:'Новый заказ',reminder:'Заказ ожидает подтверждения',escalation:'Подтверждение просрочено',presence:'Гость ожидает подтверждения присутствия',call:'Вызов официанта',bill:'Запрос счёта',reassigned:'Столик переназначен'},en:{order:'New order',reminder:'Order awaiting confirmation',escalation:'Confirmation overdue',presence:'Guest awaits presence confirmation',call:'Waiter call',bill:'Bill requested',reassigned:'Table reassigned'}};
   const localized=messages[job.subscription.locale??'uk']??messages.uk;
   await webpush.sendNotification(job.subscription, JSON.stringify({ id: job.notification_id, title: 'QR Waiter', body: localized[job.kind]??job.message, url: '/' }), { TTL: 180, topic: job.notification_id.replace(/-/g, '') });
   await db.rpc('finish_push', { p_notification: job.notification_id, p_subscription: job.subscription_id, p_success: true });
  } catch (e) {
   const status = (e as { statusCode?: number }).statusCode;
   await db.rpc('finish_push', { p_notification: job.notification_id, p_subscription: job.subscription_id, p_success: false, p_error: `Push status ${status ?? 'network'}`, p_gone: status === 404 || status === 410 });
  }
 }
 return Response.json({ processed: batch?.length ?? 0 });
});
