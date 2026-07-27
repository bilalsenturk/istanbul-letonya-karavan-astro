import type { AccountRecord } from './accountRepository.ts';
import { accountById, sessionIsActive } from './accountRepository.ts';
import { requireSession } from './session.ts';
import { UnauthorizedError } from './session.ts';
import { TripRepositoryError, type TripActor } from './tripRepository.ts';

export type AuthenticatedRequest = {
  account: AccountRecord;
  actor: TripActor;
  sessionId: string;
};

export const authenticateRequest = async (request: Request): Promise<AuthenticatedRequest> => {
  const claims = await requireSession(request);
  if (!(await sessionIsActive(claims.sessionId, claims.userId))) throw new UnauthorizedError();
  const account = await accountById(claims.userId);
  if (!account) throw new UnauthorizedError();
  return {
    account,
    actor: { userId: account.id, globalRole: account.globalRole },
    sessionId: claims.sessionId,
  };
};

export const json = (value: unknown, status = 200): Response => new Response(JSON.stringify(value), {
  status,
  headers: {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  },
});

export const errorResponse = (error: unknown): Response => {
  if (error instanceof UnauthorizedError) return json({ error: 'unauthorized', message: messageFor('unauthorized') }, 401);
  if (error instanceof TripRepositoryError) {
    const status = error.code === 'forbidden' ? 403
      : error.code === 'trip_not_found' ? 404
        : error.code === 'revision_conflict' ? 409 : 422;
    return json({ error: error.code, message: messageFor(error.code), current: error.current }, status);
  }
  const code = error instanceof Error ? error.message : 'unknown_error';
  const status = code === 'invalid_json' || code === 'invalid_request_body' ? 400
    : code === 'invalid_travel_profile' ? 422 : 500;
  return json({ error: status === 500 ? 'internal_error' : code, message: messageFor(status === 500 ? 'internal_error' : code) }, status);
};

export const requestJSON = async <T>(request: Request): Promise<T> => {
  try {
    return await request.json() as T;
  } catch {
    throw new Error('invalid_json');
  }
};

const messages: Record<string, string> = {
  unauthorized: 'Oturum açmanız gerekiyor.',
  session_revoked: 'Oturum sona erdi. Yeniden giriş yapın.',
  forbidden: 'Bu işlem için yetkiniz yok.',
  revision_conflict: 'Rota başka bir cihazda değişti. Güncel sürüm yüklendi.',
  invalid_email: 'Geçerli bir e-posta girin.',
  invalid_travel_profile: 'Seyahat profili alanlarını kontrol edin.',
  invalid_json: 'Geçerli bir istek gövdesi gönderin.',
  invalid_request_body: 'Geçerli bir istek gövdesi gönderin.',
  internal_error: 'İşlem tamamlanamadı.',
  reserved_trip_kind: 'Bu rota türü yalnızca Kuzey yolculuğuna ayrılmıştır.',
};

const messageFor = (code: string): string => messages[code] ?? 'İşlem tamamlanamadı.';
