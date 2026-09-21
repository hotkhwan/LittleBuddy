import type { Context } from 'hono';
import type { Config, Env } from '../env';
import type { TokenService } from './tokens';
import type { TutorProvider } from '../tutor/provider_interface';

export interface AuthContext {
  parentId: string;
  /** Present when the credential was a parental-approval token (bound to this clientId). */
  clientId: string | null;
  childId: string | null;
  approvalToken: string | null;
  via: 'bearer' | 'approval' | 'dev_literal';
}

export interface Vars {
  config: Config;
  now: number;
  body: unknown;
  auth: AuthContext | null;
  tokens: TokenService;
  provider: TutorProvider;
  requestId: string;
}

export type AppContext = Context<{ Bindings: Env; Variables: Vars }>;

export function requireAuth(c: AppContext): AuthContext {
  const a = c.get('auth');
  if (!a) throw new Error('route mounted outside the auth middleware');
  return a;
}
