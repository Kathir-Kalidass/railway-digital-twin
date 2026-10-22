export function makeMlClient({ config, fetchImpl = fetch }) {
  const url = config.ml?.url || 'http://127.0.0.1:8001';
  const timeoutMs = config.ml?.timeoutMs || 2000;

  async function call(path, options) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(`${url}${path}`, { ...options, signal: controller.signal });
      if (!res.ok) throw new Error(`ml status ${res.status}`);
      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  }

  return {
    detect: (jpeg) => call('/detect', {
      method: 'POST',
      headers: { 'content-type': 'image/jpeg' },
      body: jpeg,
    }),
    health: () => call('/health'),
  };
}
