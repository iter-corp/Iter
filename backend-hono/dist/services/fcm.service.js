import admin from 'firebase-admin';
import { env } from '../config/env.js';
import { db } from '../db/index.js';
import { fcmTokens } from '../db/schema/index.js';
import { eq } from 'drizzle-orm';
import fs from 'fs';
let firebaseInitialized = false;
export function initFirebase() {
    if (firebaseInitialized)
        return true;
    try {
        if (admin.apps.length > 0) {
            firebaseInitialized = true;
            return true;
        }
        const keyConfig = env.FIREBASE_SERVICE_ACCOUNT_KEY;
        if (!keyConfig) {
            console.log('ℹ️ [FCM] FIREBASE_SERVICE_ACCOUNT_KEY not provided — running FCM in mock/log mode.');
            return false;
        }
        let credentialObj;
        if (keyConfig.trim().startsWith('{')) {
            credentialObj = JSON.parse(keyConfig);
        }
        else if (fs.existsSync(keyConfig)) {
            credentialObj = JSON.parse(fs.readFileSync(keyConfig, 'utf-8'));
        }
        else {
            console.warn('⚠️ [FCM] Invalid FIREBASE_SERVICE_ACCOUNT_KEY path or JSON — running FCM in mock mode.');
            return false;
        }
        admin.initializeApp({
            credential: admin.credential.cert(credentialObj),
        });
        firebaseInitialized = true;
        console.log('✅ [FCM] Firebase Admin initialized successfully for push notifications.');
        return true;
    }
    catch (error) {
        console.error('❌ [FCM] Failed to initialize Firebase Admin:', error);
        return false;
    }
}
export async function sendPushNotification(payload) {
    const isReady = initFirebase();
    try {
        // Fetch device tokens for the target user from database
        const userTokens = await db
            .select({ token: fcmTokens.token })
            .from(fcmTokens)
            .where(eq(fcmTokens.uid, payload.targetUid));
        const tokens = userTokens.map((t) => t.token).filter((t) => Boolean(t));
        if (tokens.length === 0) {
            return;
        }
        if (!isReady) {
            console.log(`[FCM Mock Log] Push to ${payload.targetUid} (${tokens.length} tokens): "${payload.title}" - "${payload.body}"`);
            return;
        }
        const messagePayload = {
            tokens,
            notification: {
                title: payload.title,
                body: payload.body,
            },
            data: {
                type: payload.type,
                actorUid: payload.actorUid || '',
                targetId: payload.targetId || '',
                commentId: payload.commentId || '',
                ...(payload.data || {}),
            },
        };
        const response = await admin.messaging().sendEachForMulticast(messagePayload);
        if (response.failureCount > 0) {
            // Clean up stale or invalid tokens
            const tokensToRemove = [];
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    const errCode = resp.error?.code;
                    if (errCode === 'messaging/registration-token-not-registered' ||
                        errCode === 'messaging/invalid-registration-token') {
                        tokensToRemove.push(tokens[idx]);
                    }
                }
            });
            for (const badToken of tokensToRemove) {
                await db.delete(fcmTokens).where(eq(fcmTokens.token, badToken));
            }
        }
    }
    catch (error) {
        console.error('❌ [FCM] Error sending push notification:', error);
    }
}
