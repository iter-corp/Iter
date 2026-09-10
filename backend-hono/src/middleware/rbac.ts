import { Context, Next } from 'hono';
import { AppError } from './error-handler.js';

export function requireRole(allowedRoles: string | string[]) {
  const roles = Array.isArray(allowedRoles) ? allowedRoles : [allowedRoles];

  return async (c: Context, next: Next) => {
    const user = c.get('user');
    if (!user) {
      throw new AppError('Authentication required', 401, 'UNAUTHORIZED');
    }

    // Super admin has access to all roles
    if (user.role === 'admin') {
      await next();
      return;
    }

    if (!roles.includes(user.role)) {
      throw new AppError('Permission denied. Required role: ' + roles.join(' or '), 403, 'FORBIDDEN');
    }

    await next();
  };
}
