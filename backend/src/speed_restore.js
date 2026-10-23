export function restoreSpeed(train, savedKmh, { reason = 'UNKNOWN', fallbackKmh = 48, onRestore = null } = {}) {
  const restored = Number.isFinite(savedKmh) && savedKmh > 0 ? savedKmh : fallbackKmh;
  train.commandedSpeedKmh = restored;
  if (restored !== savedKmh && typeof onRestore === 'function') {
    onRestore({
      type: 'SPEED_RESTORED_FALLBACK',
      trainId: train.id,
      reason,
      restoredKmh: restored,
      attemptedSavedKmh: savedKmh ?? null,
      timestamp: new Date().toISOString(),
    });
  }
  return restored;
}
