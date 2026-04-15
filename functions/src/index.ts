import * as admin from 'firebase-admin';

import * as comments from './comments';
import * as follows from './follows';
import * as likes from './likes';
import * as live from './live';
import * as messages from './messages';
import * as notifications from './notifications';
import * as posts from './posts';
import * as translate from './translate';

admin.initializeApp();

export {
  comments,
  follows,
  likes,
  live,
  messages,
  notifications,
  posts,
  translate,
};
