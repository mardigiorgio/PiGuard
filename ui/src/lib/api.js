// Compute API base at runtime to avoid embedding localhost in prod builds.
// Fallback to window.location.origin + '/api' when VITE_API_BASE is not set.
const RUNTIME_BASE = (typeof window !== 'undefined' && window.location && window.location.origin)
  ? `${window.location.origin.replace(/\/$/, '')}/api`
  : 'http://localhost:8080/api'
const API_BASE = (import.meta.env && import.meta.env.VITE_API_BASE) || RUNTIME_BASE

// Authentication state management
function _readAuthToken() {
  try {
    return (typeof window !== 'undefined') ? localStorage.getItem('authToken') : null
  } catch {
    return null
  }
}

function _readUsername() {
  try {
    return (typeof window !== 'undefined') ? localStorage.getItem('username') : null
  } catch {
    return null
  }
}

let AUTH_TOKEN = _readAuthToken()
let USERNAME = _readUsername()

export function isAuthenticated() {
  return !!AUTH_TOKEN
}

export function getUsername() {
  return USERNAME
}

export function clearAuth() {
  AUTH_TOKEN = null
  USERNAME = null
  try {
    localStorage.removeItem('authToken')
    localStorage.removeItem('username')
  } catch {}
}

// Allow runtime API key override via localStorage or URL param 'apikey'.
function _readApiKey() {
  try {
    const sp = (typeof window !== 'undefined') ? new URLSearchParams(window.location.search) : null
    const fromQs = sp ? (sp.get('apikey') || sp.get('api_key')) : null
    if (fromQs) {
      try { localStorage.setItem('apiKey', fromQs) } catch {}
      return fromQs
    }
    const fromStore = (typeof window !== 'undefined') ? localStorage.getItem('apiKey') : null
    return fromStore || (import.meta.env && import.meta.env.VITE_API_KEY) || 'change-me'
  } catch {
    return (import.meta.env && import.meta.env.VITE_API_KEY) || 'change-me'
  }
}
let API_KEY = _readApiKey()

export function setApiKey(key) {
  API_KEY = String(key || '')
  try { localStorage.setItem('apiKey', API_KEY) } catch {}
}

async function request(path, opts = {}) {
  const headers = opts.headers || {}

  // Add authentication header (token takes precedence over API key)
  if (AUTH_TOKEN) {
    headers['Authorization'] = `Bearer ${AUTH_TOKEN}`
  } else {
    headers['X-Api-Key'] = API_KEY
  }

  if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json'
  const res = await fetch(`${API_BASE}${path}`, { ...opts, headers })
  let data = null
  try {
    data = await res.json()
  } catch {
    data = null
  }
  if (!res.ok) {
    // If 401, clear auth and let the app redirect to login
    if (res.status === 401) {
      clearAuth()
    }
    const detail = data && (data.detail || data.error || data.message)
    throw new Error(detail ? `HTTP ${res.status}: ${detail}` : `HTTP ${res.status}`)
  }
  return data
}

export async function login(username, password) {
  const res = await fetch(`${API_BASE}/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password })
  })
  const data = await res.json()
  if (!res.ok) {
    const detail = data && (data.detail || data.error || data.message)
    throw new Error(detail || 'Login failed')
  }
  // Store auth token and username
  AUTH_TOKEN = data.token
  USERNAME = data.username
  try {
    localStorage.setItem('authToken', AUTH_TOKEN)
    localStorage.setItem('username', USERNAME)
  } catch {}
  return data
}

export async function logout() {
  try {
    if (AUTH_TOKEN) {
      await fetch(`${API_BASE}/logout`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${AUTH_TOKEN}` }
      })
    }
  } catch {
    // Ignore logout errors
  } finally {
    clearAuth()
  }
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

// Admin: restart services (sensor/sniffer)
export async function postAdminRestart(serviceOrServices) {
  const payload = Array.isArray(serviceOrServices)
    ? { services: serviceOrServices }
    : { service: String(serviceOrServices) }
  return request('/admin/restart', { method: 'POST', body: JSON.stringify(payload) })
}

// Settings: deauth thresholds
export async function getDeauthSettings() {
  return request('/settings/deauth')
}
export async function postDeauthSettings(payload) {
  return request('/settings/deauth', { method: 'POST', body: JSON.stringify(payload) })
}
