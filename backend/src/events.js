export function makeEvents(max = 200) {
  const items = [];
  return {
    record(e) {
      const entry = { id: `${Date.now()}-${Math.random().toString(16).slice(2, 7)}`, time: new Date().toISOString(), ...e };
      items.unshift(entry);
      if (items.length > max) items.pop();
      return entry;
    },
    list(limit = 100) { return items.slice(0, Math.max(1, Number(limit) || 100)); },
  };
}
