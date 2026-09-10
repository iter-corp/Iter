import { WebSocket, WebSocketServer } from 'ws';
import { IncomingMessage } from 'http';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

interface ClientConnection {
  ws: WebSocket;
  uid: string;
  activeChatId?: string;
  lastHeartbeat: number;
}

export class RealtimeService {
  private wss: WebSocketServer | null = null;
  private clients: Map<string, Set<ClientConnection>> = new Map(); // uid -> Set<Connection>
  private onlineUsers: Map<string, number> = new Map(); // uid -> lastSeenMs

  init(server: import('http').Server) {
    this.wss = new WebSocketServer({ server, path: '/ws' });

    this.wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
      const url = new URL(req.url || '', `http://${req.headers.host}`);
      const token = url.searchParams.get('token');

      if (!token) {
        ws.close(4001, 'Authentication token required');
        return;
      }

      let uid = '';
      try {
        const decoded = jwt.verify(token, env.JWT_SECRET) as { sub: string };
        uid = decoded.sub;
      } catch {
        ws.close(4003, 'Invalid or expired token');
        return;
      }

      const connection: ClientConnection = {
        ws,
        uid,
        lastHeartbeat: Date.now(),
      };

      if (!this.clients.has(uid)) {
        this.clients.set(uid, new Set());
      }
      this.clients.get(uid)!.add(connection);
      this.onlineUsers.set(uid, Date.now());

      this.broadcastPresence(uid, true);

      ws.on('message', (data: string) => {
        try {
          const msg = JSON.parse(data.toString());
          this.handleMessage(connection, msg);
        } catch (e) {
          console.error('[WS] Parse error:', e);
        }
      });

      ws.on('close', () => {
        const userConnections = this.clients.get(uid);
        if (userConnections) {
          userConnections.delete(connection);
          if (userConnections.size === 0) {
            this.clients.delete(uid);
            this.onlineUsers.set(uid, Date.now());
            this.broadcastPresence(uid, false);
          }
        }
      });
    });

    console.log('⚡ [WebSocket] Realtime presence and messaging server initialized on /ws');
  }

  private handleMessage(client: ClientConnection, msg: { type: string; payload: Record<string, unknown> }) {
    switch (msg.type) {
      case 'heartbeat':
        client.lastHeartbeat = Date.now();
        this.onlineUsers.set(client.uid, Date.now());
        client.ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
        break;

      case 'enter_chat':
        client.activeChatId = String(msg.payload?.chatId ?? '');
        break;

      case 'leave_chat':
        client.activeChatId = undefined;
        break;

      case 'typing': {
        const chatId = String(msg.payload?.chatId ?? '');
        const isTyping = Boolean(msg.payload?.isTyping);
        const recipientUids = (msg.payload?.recipientUids as string[]) || [];

        for (const recipientUid of recipientUids) {
          if (recipientUid === client.uid) continue;
          this.sendToUser(recipientUid, {
            type: 'typing_update',
            chatId,
            uid: client.uid,
            isTyping,
          });
        }
        break;
      }
    }
  }

  broadcastPresence(uid: string, online: boolean) {
    const payload = JSON.stringify({
      type: 'presence_update',
      uid,
      online,
      lastSeen: Date.now(),
    });

    for (const connections of this.clients.values()) {
      for (const client of connections) {
        if (client.ws.readyState === WebSocket.OPEN) {
          client.ws.send(payload);
        }
      }
    }
  }

  sendToUser(uid: string, event: Record<string, unknown>) {
    const connections = this.clients.get(uid);
    if (!connections) return;

    const payload = JSON.stringify(event);
    for (const client of connections) {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(payload);
      }
    }
  }

  isUserOnline(uid: string): boolean {
    const conns = this.clients.get(uid);
    return Boolean(conns && conns.size > 0);
  }

  getUserLastSeen(uid: string): number | null {
    return this.onlineUsers.get(uid) || null;
  }
}

export const realtimeService = new RealtimeService();
