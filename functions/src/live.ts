import * as admin from 'firebase-admin';
import { RtcRole, RtcTokenBuilder } from 'agora-access-token';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentDeleted } from 'firebase-functions/v2/firestore';

const db = admin.firestore();

export const issueLiveToken = onCall(async (request) => {
  const channelName = String(request.data?.channelName ?? '');
  const role = String(request.data?.role ?? 'audience');
  if (channelName.length == 0) {
    throw new HttpsError('invalid-argument', 'channelName is required');
  }

  const appId = process.env.AGORA_APP_ID ?? '';
  const appCertificate = process.env.AGORA_APP_CERTIFICATE ?? '';
  const expiresInSeconds = 60 * 60;
  const expiresAt = Math.floor(Date.now() / 1000) + expiresInSeconds;
  let token: string | null = null;

  if (appId.length > 0 && appCertificate.length > 0) {
    token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      0,
      role === 'host' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER,
      expiresAt,
    );
  }

  return {
    channelName,
    role,
    appId: appId.length > 0 ? appId : null,
    token,
    expiresAt,
  };
});

export const onLiveStreamDelete = onDocumentDeleted('liveStreams/{streamId}', async (event) => {
  const streamId = event.params.streamId;

  // Cleanup marker collection if used by client analytics or chat replay.
  const markerRef = db.collection('liveStreamCleanup').doc(streamId);
  await markerRef.set({
    cleanedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});
