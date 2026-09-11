import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { appConfigs, sduiScreens, dynamicEnums } from '../db/schema/index.js';
import { eq } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth } from '../middleware/auth.js';
import { requireRole } from '../middleware/rbac.js';

export const dynamicRoutes = new Hono();

// ── 1. Remote App Config & Feature Flags ────────────────────────────────────
dynamicRoutes.get('/config', async (c) => {
  const [config] = await db.select().from(appConfigs).where(eq(appConfigs.id, 'app')).limit(1);

  if (!config) {
    return c.json({
      success: true,
      data: {
        storiesEnabled: true,
        repostsEnabled: true,
        translateEnabled: true,
        maintenanceMode: false,
        maintenanceMessage: '',
        minAppVersion: '1.0.0',
        announcement: '',
        contactEmail: 'support@iter.app',
        iosAppStoreUrl: '',
        androidPlayStoreUrl: '',
        eventTypes: ['Scholarship', 'Internship', 'Research', 'Conference', 'other'],
        profileProfessionOptions: ['Student', 'Engineer', 'Other'],
        profileFieldOptions: ['Computer Science', 'Medicine', 'Other'],
        profileAcademicLevelOptions: ['Bachelor', 'Master', 'PhD', 'Other'],
        profileGoalOptions: ['Internships', 'Scholarships', 'Networking'],
        featureFlags: {},
      },
    });
  }

  return c.json({ success: true, data: config });
});

// ── 2. Server-Driven UI (SDUI) Screen Layout ────────────────────────────────
dynamicRoutes.get('/screens/:screenId', async (c) => {
  const screenId = c.req.param('screenId')!;

  const [screen] = await db
    .select()
    .from(sduiScreens)
    .where(eq(sduiScreens.id, screenId))
    .limit(1);

  if (!screen || !screen.active) {
    return c.json({
      success: true,
      data: {
        id: screenId,
        active: false,
        layout: { type: 'vertical_stack', blocks: [] },
      },
    });
  }

  return c.json({ success: true, data: screen });
});

// ── 3. Dynamic Form Enums & Dropdowns ───────────────────────────────────────
dynamicRoutes.get('/enums', async (c) => {
  const allEnums = await db.select().from(dynamicEnums);
  const map: Record<string, unknown> = {};
  for (const item of allEnums) {
    map[item.id] = item.items;
  }
  return c.json({ success: true, data: map });
});

dynamicRoutes.get('/enums/:enumId', async (c) => {
  const enumId = c.req.param('enumId')!;
  const [item] = await db.select().from(dynamicEnums).where(eq(dynamicEnums.id, enumId)).limit(1);

  if (!item) {
    return c.json({ success: true, data: [] });
  }

  return c.json({ success: true, data: item.items });
});

// ── 4. Admin: Update SDUI Screen Layout ─────────────────────────────────────
const updateScreenSchema = z.object({
  title: z.string().min(1),
  description: z.string().optional(),
  active: z.boolean().default(true),
  layout: z.object({
    type: z.enum(['vertical_stack', 'horizontal_carousel', 'banner', 'modal', 'custom']),
    blocks: z.array(z.record(z.unknown())),
  }),
});

dynamicRoutes.post('/admin/screens/:screenId', requireAuth, requireRole('admin'), zValidator('json', updateScreenSchema), async (c) => {
  const screenId = c.req.param('screenId')!;
  const body = c.req.valid('json');

  await db
    .insert(sduiScreens)
    .values({
      id: screenId,
      title: body.title,
      description: body.description || null,
      active: body.active,
      layout: body.layout as any,
      updatedAt: new Date(),
    })
    .onDuplicateKeyUpdate({
      set: {
        title: body.title,
        description: body.description || null,
        active: body.active,
        layout: body.layout as any,
        updatedAt: new Date(),
      },
    });

  const [screen] = await db.select().from(sduiScreens).where(eq(sduiScreens.id, screenId)).limit(1);

  return c.json({ success: true, data: screen });
});

// ── 5. Admin: Update Dynamic Enum ───────────────────────────────────────────
const updateEnumSchema = z.object({
  name: z.string().min(1),
  items: z.array(z.object({
    label: z.string(),
    value: z.string(),
    icon: z.string().optional(),
    badge: z.string().optional(),
  })),
});

dynamicRoutes.post('/admin/enums/:enumId', requireAuth, requireRole('admin'), zValidator('json', updateEnumSchema), async (c) => {
  const enumId = c.req.param('enumId')!;
  const body = c.req.valid('json');

  await db
    .insert(dynamicEnums)
    .values({
      id: enumId,
      name: body.name,
      items: body.items,
      updatedAt: new Date(),
    })
    .onDuplicateKeyUpdate({
      set: {
        name: body.name,
        items: body.items,
        updatedAt: new Date(),
      },
    });

  const [item] = await db.select().from(dynamicEnums).where(eq(dynamicEnums.id, enumId)).limit(1);

  return c.json({ success: true, data: item });
});
