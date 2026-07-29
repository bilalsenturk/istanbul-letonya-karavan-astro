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
  const code = error instanceof TripRepositoryError ? error.code : error instanceof Error ? error.message : 'unknown_error';
  if (code === 'session_revoked') return json({ error: code, message: messageFor(code) }, 401);
  if (error instanceof TripRepositoryError && code === 'forbidden') return json({ error: code, message: messageFor(code) }, 403);
  if ((error instanceof TripRepositoryError && code === 'trip_not_found') || code === 'account_not_found') {
    return json({ error: code, message: messageFor(code) }, 404);
  }
  if (error instanceof TripRepositoryError && code === 'revision_conflict') {
    return json({ error: code, message: messageFor(code), current: error.current }, 409);
  }
  if (code === 'invalid_json' || code === 'invalid_request_body') {
    return json({ error: code, message: messageFor(code) }, 400);
  }
  if (code === 'invalid_travel_profile' || validationCodes.has(code)) {
    return json({ error: code, message: messageFor(code) }, 422);
  }
  return json({ error: 'internal_error', message: messageFor('internal_error') }, 500);
};

const validationCodes = new Set([
  'apple_credentials_required',
  'apple_subject_required',
  'duplicate_invite',
  'duplicate_member',
  'duplicate_stop',
  'duplicate_trip_created_event',
  'invalid_apple_nonce',
  'invalid_arrival_target',
  'invalid_email',
  'invalid_invite_role',
  'invalid_optional_string',
  'invalid_stay_details',
  'invalid_stop',
  'invalid_stop_changes',
  'invalid_stop_coordinates',
  'invalid_stop_order',
  'invalid_stop_source',
  'invalid_stops',
  'invalid_transport_mode',
  'invalid_trip_event_sequence',
  'invalid_trip_kind',
  'invalid_trip_role',
  'last_owner_required',
  'member_not_found',
  'member_user_required',
  'reserved_trip_kind',
  'stop_id_required',
  'stop_name_required',
  'stop_not_found',
  'stop_order_required',
  'too_many_stops',
  'trip_created_event_required',
  'trip_name_required',
]);

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
