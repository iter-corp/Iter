import * as admin from 'firebase-admin';

import * as comments from './comments';
import * as follows from './follows';
import * as live from './live';
import * as messages from './messages';
import * as notifications from './notifications';
import * as translate from './translate';

admin.initializeApp();

export {
  comments,
  follows,
  live,
  messages,
  notifications,
  translate,
};
