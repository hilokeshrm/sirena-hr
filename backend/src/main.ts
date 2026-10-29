import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  // Behind Caddy, the real client IP (used for office-network check-in) comes from X-Forwarded-For.
  if (process.env.TRUST_PROXY === 'true') app.set('trust proxy', 'loopback');
  app.setGlobalPrefix('api');
  // In production only the website's own origin may call the API from a browser (the mobile apps send no Origin).
  const corsOrigins = process.env.CORS_ORIGINS?.split(',').map((o) => o.trim()).filter(Boolean);
  app.enableCors({ origin: corsOrigins?.length ? corsOrigins : true, credentials: true });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  await app.listen(Number(process.env.PORT ?? 3000), '0.0.0.0');
  console.log(`Sirena HR API on http://localhost:${process.env.PORT ?? 3000}/api`);
}
bootstrap();
