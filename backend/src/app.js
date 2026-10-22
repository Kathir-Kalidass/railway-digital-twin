import express from 'express';
import cors from 'cors';
import { authRouter } from './routes/auth.js';
import { healthRouter } from './routes/health.js';
import { controlRouter } from './routes/control.js';
import { wrongLineRouter } from './routes/wrong_line.js';
import { stateRouter } from './routes/state.js';
import { wildlifeRouter } from './routes/wildlife.js';
import { makeWildlifeCommands } from './wildlife_commands.js';

export function createApp(deps) {
  const app = express();
  const commands = deps.commands || makeWildlifeCommands(deps);
  app.use(cors());
  app.use(wildlifeRouter({ ...deps, commands }));
  app.use(express.json({ limit: '32kb' }));
  app.use(authRouter(deps));
  app.use(healthRouter(deps));
  app.use(controlRouter(deps));
  app.use(wrongLineRouter(deps));
  app.use(stateRouter(deps));
  return app;
}
