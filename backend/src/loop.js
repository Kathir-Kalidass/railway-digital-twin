export function makeLoop({ state, bus, config, intervalMs = config.simulation?.tickMs ?? 500 }) {
  const dtSec = intervalMs / 1000;
  let timer = null;

  function step() {
    state.tick(dtSec);
    return bus.snapshot();
  }

  function start() {
    if (timer) return false;
    timer = setInterval(step, intervalMs);
    if (typeof timer.unref === 'function') timer.unref();
    return true;
  }

  function stop() {
    if (!timer) return false;
    clearInterval(timer);
    timer = null;
    return true;
  }

  return { start, stop, step, isRunning: () => timer !== null };
}
