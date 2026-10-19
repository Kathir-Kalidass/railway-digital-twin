import { Router } from 'express';

export function authRouter({ auth }) {
  const router = Router();
  router.post('/api/auth/login', (req, res) => {
    const result = auth.login(req.body?.username, req.body?.password);
    if (!result.ok) return res.status(401).json({ error: result.reason });
    return res.json({ token: result.token, user: result.user });
  });
  router.get('/api/me', auth.requireAuth, (req, res) => res.json({ user: req.user }));
  return router;
}
