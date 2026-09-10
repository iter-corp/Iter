import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { polls, pollVotes, users } from '../db/schema/index.js';
import { eq, and, sql } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { randomBytes } from 'crypto';

export const pollRoutes = new Hono();

// ── 1. Create Poll ──────────────────────────────────────────────────────────
const createPollSchema = z.object({
  question: z.string().min(3).max(300),
  options: z.array(z.string().min(1)).min(2).max(10),
  visibility: z.enum(['public', 'secret']).default('public'),
});

pollRoutes.post('/', requireAuth, zValidator('json', createPollSchema), async (c) => {
  const uid = c.get('uid');
  const { question, options, visibility } = c.req.valid('json');

  const pollId = `pol_${randomBytes(12).toString('hex')}`;
  const [newPoll] = await db
    .insert(polls)
    .values({
      id: pollId,
      question,
      options,
      createdByUid: uid,
      visibility,
    })
    .returning();

  return c.json({ success: true, data: newPoll }, 201);
});

// ── 2. Get Poll & Results ───────────────────────────────────────────────────
pollRoutes.get('/:id', optionalAuth, async (c) => {
  const pollId = c.req.param('id')!;
  const viewerUid = c.get('uid');

  const [poll] = await db.select().from(polls).where(eq(polls.id, pollId)).limit(1);
  if (!poll) throw new AppError('Poll not found', 404, 'NOT_FOUND');

  // Count votes per option
  const votes = await db.select().from(pollVotes).where(eq(pollVotes.pollId, pollId));
  const counts: Record<number, number> = {};
  for (let i = 0; i < poll.options.length; i++) counts[i] = 0;

  let myVote: number | null = null;
  for (const v of votes) {
    counts[v.optionIndex] = (counts[v.optionIndex] || 0) + 1;
    if (viewerUid && v.uid === viewerUid) {
      myVote = v.optionIndex;
    }
  }

  return c.json({
    success: true,
    data: {
      ...poll,
      totalVotes: votes.length,
      optionCounts: counts,
      myVote,
    },
  });
});

// ── 3. Vote on Poll ─────────────────────────────────────────────────────────
const voteSchema = z.object({
  optionIndex: z.number().int().min(0),
});

pollRoutes.post('/:id/vote', requireAuth, zValidator('json', voteSchema), async (c) => {
  const pollId = c.req.param('id')!;
  const uid = c.get('uid');
  const { optionIndex } = c.req.valid('json');

  const [poll] = await db.select().from(polls).where(eq(polls.id, pollId)).limit(1);
  if (!poll) throw new AppError('Poll not found', 404, 'NOT_FOUND');
  if (poll.closed) throw new AppError('This poll is closed for voting', 400, 'POLL_CLOSED');
  if (optionIndex >= poll.options.length) throw new AppError('Invalid option index', 400, 'INVALID_OPTION');

  const voteId = `${pollId}_${uid}`;
  await db
    .insert(pollVotes)
    .values({ id: voteId, pollId, uid, optionIndex })
    .onConflictDoUpdate({
      target: [pollVotes.pollId, pollVotes.uid],
      set: { optionIndex, createdAt: new Date() },
    });

  return c.json({ success: true, votedIndex: optionIndex });
});
