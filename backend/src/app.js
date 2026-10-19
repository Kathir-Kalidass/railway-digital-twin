import express from 'express';
import cors from 'cors';
import { authRouter } from './routes/auth.js';
import { healthRouter } from './routes/health.js';

export function createApp(deps) {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '32kb' }));
  app.use(authRouter(deps));
  app.use(healthRouter(deps));
  return app;
}
