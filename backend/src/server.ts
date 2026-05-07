import { env } from "./config/runtime-env.js";
import { buildApp } from "./http/app.js";

const app = await buildApp();

try {
  await app.ready();
  await (app as unknown as { readyCheck: () => Promise<void> }).readyCheck();
  await app.listen({ host: env.HOST, port: env.PORT });
} catch (error) {
  app.log.error(error);
  process.exit(1);
}
