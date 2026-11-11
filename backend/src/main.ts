import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { corsOrigins, securityHeaders } from './common/security';

async function bootstrap() {
  const production = process.env.TRUST_PROXY === 'true' || process.env.NODE_ENV === 'production';
  // JSON bodies are small forms; file uploads go through multer with their own limit.
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bodyParser: false });
  app.useBodyParser('json', { limit: '256kb' });
  app.useBodyParser('urlencoded', { limit: '64kb', extended: false });
  app.disable('x-powered-by');
  app.use(securityHeaders);
  // Behind Caddy, the real client IP (used for office-network check-in) comes from X-Forwarded-For.
  if (process.env.TRUST_PROXY === 'true') app.set('trust proxy', 'loopback');
  app.setGlobalPrefix('api');
  // Only the website's own origin may call the API from a browser (the mobile apps send no Origin).
  app.enableCors({ origin: corsOrigins(process.env.CORS_ORIGINS, production), credentials: false, maxAge: 600 });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, forbidUnknownValues: true, transform: true }));
  app.enableShutdownHooks();
  // On the server Caddy is the only way in, so listen on loopback there; HOST=0.0.0.0 lets phones on the LAN reach a dev API.
  const host = process.env.HOST ?? (production ? '127.0.0.1' : '0.0.0.0');
  await app.listen(Number(process.env.PORT ?? 3000), host);
  console.log(`Sirena HR API on http://${host}:${process.env.PORT ?? 3000}/api`);
}
bootstrap();
