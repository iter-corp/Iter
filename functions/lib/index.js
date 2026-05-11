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
exports.translate = exports.posts = exports.notifications = exports.messages = exports.live = exports.likes = exports.follows = exports.events = exports.comments = exports.adminUsers = void 0;
const admin = __importStar(require("firebase-admin"));
const adminUsers = __importStar(require("./adminUsers"));
exports.adminUsers = adminUsers;
const comments = __importStar(require("./comments"));
exports.comments = comments;
const events = __importStar(require("./events"));
exports.events = events;
const follows = __importStar(require("./follows"));
exports.follows = follows;
const likes = __importStar(require("./likes"));
exports.likes = likes;
const live = __importStar(require("./live"));
exports.live = live;
const messages = __importStar(require("./messages"));
exports.messages = messages;
const notifications = __importStar(require("./notifications"));
exports.notifications = notifications;
const posts = __importStar(require("./posts"));
exports.posts = posts;
const translate = __importStar(require("./translate"));
exports.translate = translate;
admin.initializeApp();
