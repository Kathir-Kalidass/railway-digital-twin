export const PERMISSIONS = {
  viewer: ['state:read', 'events:read'],
  operator: ['state:read', 'events:read', 'control:issue', 'speed:set', 'route:set'],
  admin: ['state:read', 'events:read', 'control:issue', 'speed:set', 'route:set', 'audit:read', 'users:manage'],
};

export function hasPermission(role, perm) {
  return (PERMISSIONS[role] || []).includes(perm);
}

export function requirePermission(perm) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'unauthorized' });
    if (!hasPermission(req.user.role, perm)) return res.status(403).json({ error: 'forbidden' });
    return next();
  };
}
