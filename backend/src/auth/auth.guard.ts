import { CanActivate, createParamDecorator, ExecutionContext, ForbiddenException, Injectable, SetMetadata, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { AccessService, Actor, AppAbility } from '../access/access.service';

export const IS_PUBLIC = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC, true);

export const TEMP_PASSWORD_OK = 'tempPasswordOk';
/** Routes someone signed in with a temporary password may still use (to see who they are and change it). */
export const AllowTemporaryPassword = () => SetMetadata(TEMP_PASSWORD_OK, true);

export interface TokenPayload {
  sub: string;
  iat?: number;
  fid?: string;
}

export interface AuthedRequest {
  actor: Actor;
  ability: AppAbility;
  headers: Record<string, string | undefined>;
  ip?: string;
}

/** Global guard: every route needs a valid token unless marked @Public(). */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private jwt: JwtService, private access: AccessService, private reflector: Reflector) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, [ctx.getHandler(), ctx.getClass()])) return true;
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const header = req.headers['authorization'] ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw new UnauthorizedException();
    let payload: TokenPayload;
    try {
      payload = await this.jwt.verifyAsync<TokenPayload>(token);
    } catch {
      throw new UnauthorizedException();
    }
    // Download-link tokens only work for that one file, never as a sign-in.
    if (payload.fid || typeof payload.sub !== 'string') throw new UnauthorizedException();
    req.actor = await this.access.loadActor(payload.sub, payload.iat);
    // The app sends people with a temporary password to the change-password screen; the API enforces it too.
    if (req.actor.mustChangePassword && !this.reflector.getAllAndOverride<boolean>(TEMP_PASSWORD_OK, [ctx.getHandler(), ctx.getClass()])) {
      throw new ForbiddenException('Choose a new password to continue');
    }
    req.ability = this.access.ability(req.actor);
    return true;
  }
}

export const CurrentActor = createParamDecorator((_: unknown, ctx: ExecutionContext) => ctx.switchToHttp().getRequest<AuthedRequest>().actor);
export const CurrentAbility = createParamDecorator((_: unknown, ctx: ExecutionContext) => ctx.switchToHttp().getRequest<AuthedRequest>().ability);
