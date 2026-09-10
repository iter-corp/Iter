import { ZodError } from 'zod';
export class AppError extends Error {
    statusCode;
    code;
    details;
    constructor(message, statusCode = 400, code = 'BAD_REQUEST', details) {
        super(message);
        this.name = 'AppError';
        this.statusCode = statusCode;
        this.code = code;
        this.details = details;
    }
}
export function errorHandler(err, c) {
    console.error('[Unhandled Error]', err);
    if (err instanceof AppError) {
        return c.json({
            success: false,
            error: {
                code: err.code,
                message: err.message,
                details: err.details,
            },
        }, err.statusCode);
    }
    if (err instanceof ZodError) {
        return c.json({
            success: false,
            error: {
                code: 'VALIDATION_ERROR',
                message: 'Invalid request parameters',
                details: err.flatten().fieldErrors,
            },
        }, 400);
    }
    return c.json({
        success: false,
        error: {
            code: 'INTERNAL_SERVER_ERROR',
            message: process.env.NODE_ENV === 'production' ? 'An unexpected server error occurred' : err.message,
        },
    }, 500);
}
