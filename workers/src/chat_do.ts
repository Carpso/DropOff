// ChatRoom Durable Object — realtime chat over hibernating WebSockets.
// One DO instance per chat thread (idFromName('thread-<id>')).
//
// Auth (any one of):
//   - X-Api-Key: <API_AUTH_KEY>                 -> ops
//   - Authorization: Bearer <JWT>               -> seller / rider / courier / ops (from DB)
//   - ?tracking_token=<token>                   -> recipient of that thread's job
//
// Client protocol (JSON):
//   -> { "type": "send", "body": "text" }
//   <- { "type": "message", id, sender_phone, sender_role, body, created_at }
// REST endpoints remain the fallback; nothing here is required to chat.

import { DurableObject } from 'cloudflare:workers';
import { verifyJwtClaims } from './auth';
import type { Env } from './lipila';
import { sendToPhone } from './push';
import { containsAbuse, chatSuspendedUntil, recordAbuseStrike } from './moderation';

interface ClientInfo { role: string; phone: string }

const MAX_BODY = 500;

export class ChatRoom extends DurableObject {
  private get db(): D1Database { return (this.env as any).DB; }
  private get envAny(): any { return this.env as any; }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
      return new Response('websocket upgrade required', { status: 426 });
    }
    const url = new URL(request.url);
    const threadId = Number(url.pathname.split('/').filter(Boolean).pop());
    if (!Number.isFinite(threadId)) return new Response('bad thread', { status: 400 });

    const client = await this.authorize(request, threadId);
    if (!client) return new Response('unauthorized', { status: 401 });

    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    (pair[1] as any).serializeAttachment({ ...client, threadId });

    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    try {
      if (typeof message !== 'string') return;
      let parsed: any;
    try { parsed = JSON.parse(message); } catch { return; }
    if (parsed?.type !== 'send') return;
    const body = String(parsed.body ?? '').trim().slice(0, MAX_BODY);
    if (!body) return;
    // Realtime path mirrors the REST gate exactly (moderation.ts): suspension
    // first, then abuse — a profanity-hit still counts as an automatic strike.
    const client = (ws as any).deserializeAttachment() as (ClientInfo & { threadId: number }) | undefined;
    if (!client) { ws.close(1011, 'no identity'); return; }
    const suspended = await chatSuspendedUntil(this.env as Env, client.phone);
    if (suspended) {
      ws.send(JSON.stringify({ type: 'error', error: 'chat_suspended', until: suspended }));
      return;
    }
    if (containsAbuse(body)) {
      await recordAbuseStrike(this.env as Env, client.phone).catch(() => {});
      ws.send(JSON.stringify({ type: 'error', error: 'message_blocked' }));
      return;
    }
    const threadId = Number(client.threadId);
    const thread = await this.db.prepare('SELECT id, kind, job_id, phone FROM chat_threads WHERE id = ?1')
      .bind(threadId).first<any>();
    if (!thread) { ws.close(1011, 'thread gone'); return; }

    const { meta } = await this.db.prepare(
      `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, ?3, ?4)`,
    ).bind(threadId, client.phone, client.role, body).run();
    await this.db.prepare(
      `INSERT INTO chat_reads (thread_id, phone, last_read_id) VALUES (?1, ?2, ?3)
        ON CONFLICT(thread_id, phone) DO UPDATE SET last_read_id = MAX(chat_reads.last_read_id, excluded.last_read_id)`,
    ).bind(threadId, client.phone, meta.last_row_id as number).run();

    const outgoing = JSON.stringify({
      type: 'message', id: meta.last_row_id, sender_phone: client.phone,
      sender_role: client.role, body, created_at: new Date().toISOString().slice(0, 19).replace('T', ' '),
    });
    for (const socket of this.ctx.getWebSockets()) {
      try {
        // Each live socket belongs to one viewer: skip anyone the sender has
        // been blocked by (their next full refresh shows nothing either).
        const viewer = (socket as any).deserializeAttachment() as (ClientInfo & { threadId: number }) | undefined;
        if (viewer?.phone && viewer.phone !== client.phone && viewer.phone !== 'ops') {
          const blocked = await this.db.prepare(
            'SELECT 1 FROM user_blocks WHERE blocker = ?1 AND blocked = ?2',
          ).bind(viewer.phone, client.phone).first();
          if (blocked) continue;
        }
        socket.send(outgoing);
      } catch { /* stale socket — hibernation cleans up */ }
    }
    await this.notifyOthers(thread, client, body).catch(() => {});
  } catch (e) {
    console.error('ws webSocketMessage error:', String(e));
  }
}

  private async notifyOthers(thread: any, from: ClientInfo, body: string): Promise<void> {
    const env = this.envAny;
    const targets = new Set<string>();
    if (thread.job_id) {
      const job = await this.db.prepare('SELECT sender_phone, recipient_phone, rider_id FROM jobs WHERE id = ?1')
        .bind(thread.job_id).first<any>();
      if (job?.sender_phone) targets.add(job.sender_phone);
      if (job?.recipient_phone) targets.add(job.recipient_phone);
      if (job?.rider_id) {
        const rider = await this.db.prepare('SELECT phone FROM riders WHERE id = ?1').bind(job.rider_id).first<any>();
        if (rider?.phone) targets.add(rider.phone);
      }
    } else if (thread.phone) {
      targets.add(thread.phone);
      if (env.OWNER_PHONE) targets.add(env.OWNER_PHONE);
    }
    targets.delete(from.phone);
    for (const t of targets) {
      await sendToPhone(env, t, {
        title: 'New DropOff message',
        body: body.slice(0, 60),
        data: { kind: 'chat', thread_id: String(thread.id) },
      });
    }
  }

  private async authorize(request: Request, threadId: number): Promise<ClientInfo | null> {
    const env: any = this.envAny;
    const thread = await this.db.prepare('SELECT id, kind, job_id, phone FROM chat_threads WHERE id = ?1')
      .bind(threadId).first<any>();
    if (!thread) return null;

    if (request.headers.get('X-Api-Key') === env.API_AUTH_KEY) return { role: 'ops', phone: 'ops' };

    const bearer = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '') ?? '';
    if (bearer) {
      const claims = await verifyJwtClaims(bearer, env.JWT_SECRET);
      if (claims?.phone) {
        const phone = claims.phone;
        if (thread.kind === 'support') {
          if (thread.phone === phone) return { role: 'seller', phone };
        } else if (thread.job_id) {
          const job = await this.db.prepare('SELECT id, sender_phone, recipient_phone, courier_id, rider_id FROM jobs WHERE id = ?1')
            .bind(thread.job_id).first<any>();
          if (job) {
            if (job.sender_phone === phone) return { role: 'seller', phone };
            if (job.recipient_phone === phone) return { role: 'recipient', phone };
            const user = await this.db.prepare('SELECT role, courier_id FROM auth_users WHERE phone = ?1').bind(phone).first<any>();
            if (user?.role === 'ops') return { role: 'ops', phone };
            if (user?.role === 'partner' && user.courier_id != null && Number(user.courier_id) === Number(job.courier_id)) {
              return { role: 'courier', phone };
            }
            if (job.rider_id) {
              const rider = await this.db.prepare('SELECT phone FROM riders WHERE id = ?1').bind(job.rider_id).first<any>();
              if (rider?.phone === phone) return { role: 'rider', phone };
            }
          }
        }
      }
    }

    const trackingToken = new URL(request.url).searchParams.get('tracking_token');
    if (trackingToken && thread.job_id) {
      const row: any = await this.db.prepare(
        `SELECT t.job_id FROM tracking_tokens t WHERE t.token = ?1 AND (t.expires_at IS NULL OR t.expires_at > datetime('now'))`,
      ).bind(trackingToken).first();
      if (row && Number(row.job_id) === Number(thread.job_id)) {
        const job: any = await env.DB.prepare('SELECT recipient_phone FROM jobs WHERE id = ?1').bind(row.job_id).first();
        if (job?.recipient_phone) return { role: 'recipient', phone: job.recipient_phone };
      }
    }
    return null;
  }
}
