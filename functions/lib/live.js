"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onLiveStreamDelete = exports.issueLiveToken = void 0;
const admin = __importStar(require("firebase-admin"));
const agora_access_token_1 = require("agora-access-token");
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const db = admin.firestore();
exports.issueLiveToken = (0, https_1.onCall)(async (request) => {
    const channelName = String(request.data?.channelName ?? '');
    const role = String(request.data?.role ?? 'audience');
    if (channelName.length == 0) {
        throw new https_1.HttpsError('invalid-argument', 'channelName is required');
    }
    const appId = process.env.AGORA_APP_ID ?? '';
    const appCertificate = process.env.AGORA_APP_CERTIFICATE ?? '';
    const expiresInSeconds = 60 * 60;
    const expiresAt = Math.floor(Date.now() / 1000) + expiresInSeconds;
    let token = null;
    if (appId.length > 0 && appCertificate.length > 0) {
        token = agora_access_token_1.RtcTokenBuilder.buildTokenWithUid(appId, appCertificate, channelName, 0, role === 'host' ? agora_access_token_1.RtcRole.PUBLISHER : agora_access_token_1.RtcRole.SUBSCRIBER, expiresAt);
    }
    return {
        channelName,
        role,
        appId: appId.length > 0 ? appId : null,
        token,
        expiresAt,
    };
});
exports.onLiveStreamDelete = (0, firestore_1.onDocumentDeleted)('liveStreams/{streamId}', async (event) => {
    const streamId = event.params.streamId;
    // Cleanup marker collection if used by client analytics or chat replay.
    const markerRef = db.collection('liveStreamCleanup').doc(streamId);
    await markerRef.set({
        cleanedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
});
