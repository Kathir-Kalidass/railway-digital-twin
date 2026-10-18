import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

export function makeAuth({ db, config }) {
  const findByUsername = db.prepare('SELECT * FROM users WHERE username = ?');
  const insertUser = db.prepare(
    'INSERT INTO users (username,password_hash,role,created_at) VALUES (?,?,?,?)'
  );

  function seedUsers() {
    for (const u of config.seedUsers) {
      if (!findByUsername.get(u.username)) {
        insertUser.run(u.username, bcrypt.hashSync(u.password, config.bcryptRounds), u.role, new Date().toISOString());
      }
    }
  }

  function login(username, password) {
    const user = findByUsername.get(String(username || ''));
    if (!user || !bcrypt.compareSync(String(password || ''), user.password_hash)) {
      return { ok: false, reason: 'invalid credentials' };
    }
    const token = jwt.sign(
      { sub: user.id, username: user.username, role: user.role },
      config.jwtSecret,
      { expiresIn: config.jwtExpiresIn }
    );
    return { ok: true, token, user: { username: user.username, role: user.role } };
  }

  function verifyToken(token) {
    try {
      return { ok: true, user: jwt.verify(String(token || ''), config.jwtSecret) };
    } catch (e) {
      return { ok: false, reason: e.message };
    }
  }

  function requireAuth(req, res, next) {
    const header = String(req.headers.authorization || '');
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    const result = verifyToken(token);
    if (!result.ok) return res.status(401).json({ error: 'unauthorized' });
    req.user = { id: result.user.sub, username: result.user.username, role: result.user.role };
    return next();
  }

  return { seedUsers, login, verifyToken, requireAuth };
}
