import express from 'express';
import cors from 'cors';
import { authRouter } from './routes/auth.js';
import { healthRouter } from './routes/health.js';
import { controlRouter } from './routes/control.js';
import { stateRouter } from './routes/state.js';
import { simulationRouter } from './routes/simulation.js';

export function createApp(deps) {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '32kb' }));
  app.use(authRouter(deps));
  app.use(healthRouter(deps));
  app.use(controlRouter(deps));
  app.use(stateRouter(deps));
  app.use(simulationRouter(deps));
  return app;
}
