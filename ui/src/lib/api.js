const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:8080/api'
const API_KEY = import.meta.env.VITE_API_KEY || 'change-me'

async function request(path, opts = {}) {
  const headers = opts.headers || {}
  headers['X-Api-Key'] = API_KEY
  if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json'
  const res = await fetch(`${API_BASE}${path}`, { ...opts, headers })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return await res.json()
}

export async function getOverview() {
  return request('/overview')
}
export async function getAlerts(limit = 100) {
  return request(`/alerts?limit=${limit}`)
}
export async function getSSIDs() {
  return request('/ssids')
}
export async function getDefense() {
  return request('/defense')
}
export async function postDefense(payload) {
  return request('/defense', { method: 'POST', body: JSON.stringify(payload) })
}

export function sse(url, onData) {
  const es = new EventSource(`${API_BASE}${url}`)
  es.onmessage = (ev) => { try { onData(JSON.parse(ev.data)) } catch {} }
  return es
}

// Interface & capture
export async function getIfaces() {
  return request('/ifaces')
}
export async function getIface(dev) {
  const q = dev ? `?dev=${encodeURIComponent(dev)}` : ''
  return request(`/iface${q}`)
}
export async function getCapture() {
  return request('/capture')
}
export async function postCapture(payload) {
  return request('/capture', { method: 'POST', body: JSON.stringify(payload) })
}
export async function postMonitor(payload) {
  return request('/iface/monitor', { method: 'POST', body: JSON.stringify(payload) })
}
export async function postChannel(payload) {
  return request('/iface/channel', { method: 'POST', body: JSON.stringify(payload) })
}
export async function postMonitorClone(payload) {
  return request('/iface/monitor_clone', { method: 'POST', body: JSON.stringify(payload) })
}
// Removed: postSnifferRestart (sniffer restarts are not needed; hopper hot-reloads config)

// Logs
export async function getLogs({ since_id = null, limit = 200, source = '' } = {}) {
  const params = new URLSearchParams()
  if (since_id != null) params.set('since_id', String(since_id))
  if (limit) params.set('limit', String(limit))
  if (source) params.set('source', source)
  const q = params.toString() ? `?${params.toString()}` : ''
  return request(`/logs${q}`)
}

export async function postAdminClear(tables = ['events','alerts']) {
  return request('/admin/clear', { method: 'POST', body: JSON.stringify({ tables }) })
}
