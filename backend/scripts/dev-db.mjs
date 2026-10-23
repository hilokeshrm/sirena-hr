// Runs a local PostgreSQL for development without Docker or an installer.
// Data lives in backend/.pgdata. Production uses a normal PostgreSQL service.
import EmbeddedPostgres from 'embedded-postgres';
import { existsSync } from 'node:fs';
import path from 'node:path';

const dataDir = path.resolve(process.cwd(), '.pgdata');
const pg = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: 'postgres',
  password: 'hrdev',
  port: 5433,
  persistent: true,
});

const fresh = !existsSync(dataDir);
if (fresh) await pg.initialise();
await pg.start();
if (fresh) await pg.createDatabase('sirena_hr');
console.log('PostgreSQL running on localhost:5433 (db: sirena_hr). Ctrl+C to stop.');

const stop = async () => {
  await pg.stop();
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
setInterval(() => {}, 1 << 30);
