import type { Env } from './lipila';
import { sendSms } from './sms';

// Queues skeleton — not wired into the live Worker yet.
//
// Why: SMS, FCM and receipt emails currently run inside `waitUntil`, which is
// fine at today's volume but ties delivery to a single request's lifetime. When
// send volume or provider latency grows, enable this consumer:
//
//   1. npx wrangler queues create dropoff-notify
//   2. Add to wrangler.toml:
//        [[queues.producers]]
//        binding = "NOTIFY"
//        queue = "dropoff-notify"
//        [[queues.consumers]]
//        queue = "dropoff-notify"
//        max_batch_size = 20
//        max_batch_timeout = 5
//   3. In index.ts export { handleQueue } from './queues' and change
//      sendSms(...) call sites to `env.NOTIFY.send({ kind: 'sms', ... })`.
//
// Messages are idempotent: an SMS can be re-sent, a push can be re-sent; nothing
// here touches money or job state.
export type NotifyMessage =
  | { kind: 'sms'; to: string; body: string }
  | { kind: 'push'; phone: string; title: string; body: string; data?: Record<string, string> };

export async function handleQueue(
  batch: MessageBatch<NotifyMessage>,
  env: Env,
): Promise<void> {
  for (const message of batch.messages) {
    try {
      if (message.body.kind === 'sms') {
        await sendSms(env, message.body.to, message.body.body);
      } else {
        const { sendToPhone } = await import('./push');
        await sendToPhone(env, message.body.phone, {
          title: message.body.title,
          body: message.body.body,
          data: message.body.data ?? {},
        });
      }
      message.ack();
    } catch {
      message.retry();
    }
  }
}
