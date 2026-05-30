/**
 * Factorio AI Builder - Bridge Client
 * Shared HTTP client for all tool modules.
 */

const DEFAULT_BRIDGE_URL = "http://localhost:9380";

export function getBridgeUrl(ctx) {
  // Read from plugin config if available
  try {
    return ctx?.config?.bridgeUrl || DEFAULT_BRIDGE_URL;
  } catch {
    return DEFAULT_BRIDGE_URL;
  }
}

export async function api(ctx, method, path, body = null) {
  const base = getBridgeUrl(ctx);
  const url = `${base}${path}`;
  const options = {
    method,
    headers: { "Content-Type": "application/json" },
  };
  if (body) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(url, options);
  const data = await response.json();

  if (!response.ok) {
    const detail = data?.detail || data?.error || JSON.stringify(data);
    throw new Error(`Bridge error (${response.status}): ${detail}`);
  }

  return data;
}

export async function get(ctx, path) {
  return api(ctx, "GET", path);
}

export async function post(ctx, path, body) {
  return api(ctx, "POST", path, body);
}

export async function del(ctx, path) {
  return api(ctx, "DELETE", path);
}
