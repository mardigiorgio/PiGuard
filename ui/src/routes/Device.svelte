<script>
  import { onMount } from 'svelte'
  import { getIfaces, getIface, getCapture, postCapture, postMonitor, postMonitorClone, postChannel } from '../lib/api'

  let ifaces = []
  let dev = ''
  let info = null
  let chan = '6'
  let msg = ''
  let err = ''
  let hopEnabled = false
  let hopMode = 'lock' // 'lock' | 'list' | 'all'
  let hopListCsv = ''
  let lockChan = '11'
  let dwellMs = '100'

  async function refreshInfo() {
    err = ''
    try {
      info = await getIface(dev)
      chan = info && info.channel ? String(info.channel) : '6'
    } catch (e) {
      info = null
      err = e.message
    }
  }

  async function load() {
    err = msg = ''
    try {
      const cap = await getCapture()
      dev = cap && cap.iface ? cap.iface : ''
      hopEnabled = !!(cap && cap.hop && cap.hop.enabled)
      hopMode = (cap && cap.hop && cap.hop.mode) ? String(cap.hop.mode) : (hopEnabled ? 'all' : 'lock')
      lockChan = String((cap && cap.hop && cap.hop.lock_channel) || chan || '11')
      const list = (cap && cap.hop && cap.hop.list_channels) || []
      hopListCsv = list.join(',')
      dwellMs = String((cap && cap.hop && cap.hop.dwell_ms) || '100')
    } catch {}
    try {
      ifaces = await getIfaces()
      if (!dev && ifaces.length > 0) dev = ifaces[0].name
    } catch (e) {
      err = e.message
    }
    if (dev) await refreshInfo()
  }
  onMount(load)
  // Periodically refresh current iface info to reflect live channel updates
  let pollTimer
  onMount(() => {
    pollTimer = setInterval(() => {
      if (dev) refreshInfo()
    }, 1000) // Poll every 1 second for live channel updates
    return () => clearInterval(pollTimer)
  })

  async function saveConfig() {
    err = msg = ''
    try {
      await postCapture({ iface: dev })
      msg = 'Saved capture.iface.'
    } catch (e) {
      err = e.message
    }
  }

  async function makeMonitor() {
    err = msg = ''
    try {
      await postMonitor({ dev, channel: chan ? parseInt(chan) : undefined, force: true })
      msg = `Interface ${dev} set to monitor and up.`
      await refreshInfo()
    } catch (e) {
      // If in-place switch is not supported or device busy, suggest/try creating monitor clone
      if ((e.message || '').includes('409') || (e.message || '').toLowerCase().includes('monitor_clone')) {
        try {
          const name = dev.endsWith('mon') ? dev : `${dev}mon`
          await postMonitorClone({ dev, name, channel: chan ? parseInt(chan) : undefined, make_default: true })
          msg = `Created monitor interface ${name} and set as capture.iface.`
          await load()
          return
        } catch (e2) {
          err = e2.message
          return
        }
      }
      err = e.message
    }
  }

  async function createMonitorIface() {
    err = msg = ''
    try {
      const name = dev.endsWith('mon') ? dev : `${dev}mon`
      await postMonitorClone({ dev, name, channel: chan ? parseInt(chan) : undefined, make_default: true })
      msg = `Created monitor interface ${name} and set as capture.iface.`
      await load()
    } catch (e) {
      err = e.message
    }
  }

  // Restart removed: hopper hot-reloads from YAML; no manual restart needed

  async function applyHop() {
    err = msg = ''
    try {
      const body = { hop: { enabled: hopEnabled, mode: hopMode } }
      if (hopMode === 'lock') {
        const ch = parseInt(lockChan)
        if (!isNaN(ch)) {
          body.hop.lock_channel = ch
          // Don't manually set channel - let the hopper handle it when enabled
          // Only set manually if hopping is disabled
          if (!hopEnabled) {
            await postChannel({ dev, channel: ch })
          }
          msg = `Locked to channel ${ch}.`
        }
      } else if (hopMode === 'list') {
        const list = (hopListCsv || '')
          .split(/[\s,]+/)
          .map(x => parseInt(x))
          .filter(x => !isNaN(x))
        body.hop.list_channels = list
        msg = `Hopping ${list.length} channels.`
      } else if (hopMode === 'all') {
        msg = 'Hopping all configured bands.'
      }
      const dms = parseInt(dwellMs)
      if (!isNaN(dms) && dms > 0) body.hop.dwell_ms = dms
      await postCapture(body)
    } catch (e) {
      err = e.message
    }
  }
</script>

<div class="space-y-4">
  <div>
    <label class="block text-sm text-slate-600 mb-1">Wireless Interface</label>
    <div class="flex gap-2">
      <select class="border rounded px-2 py-1" bind:value={dev} on:change={refreshInfo}>
        {#each ifaces as i}
          <option value={i.name}>{i.name} ({i.type || 'unknown'})</option>
        {/each}
      </select>
      <button class="px-3 py-1 rounded border" on:click={saveConfig}>Save as capture.iface</button>
    </div>
  </div>

  <div class="text-sm">
    {#if info}
      <div>Exists: <span class="font-mono">{String(info.exists)}</span></div>
      <div>Up: <span class="font-mono">{String(info.up)}</span></div>
      <div>Type: <span class="font-mono">{info.type || '-'}</span></div>
      <div class="flex items-center gap-2">
        <span>Current Channel:</span>
        <span class="font-mono text-lg font-bold text-blue-600 bg-blue-50 px-2 py-1 rounded">{info.channel ?? '-'}</span>
        {#if info.freq}
          <span class="text-slate-500">({info.freq} MHz{info.band ? ', ' + info.band + ' GHz' : ''})</span>
        {/if}
      </div>
    {/if}
  </div>

  <div>
    <label class="block text-sm text-slate-600 mb-1">Hopping Mode</label>
    <div class="flex flex-col gap-2 text-sm md:flex-row md:items-center md:gap-6">
      <label class="inline-flex items-center gap-2">
        <input type="radio" name="hopmode" value="lock" bind:group={hopMode} />
        <span>Lock channel</span>
      </label>
      <label class="inline-flex items-center gap-2">
        <input type="radio" name="hopmode" value="list" bind:group={hopMode} />
        <span>Hop specified</span>
      </label>
      <label class="inline-flex items-center gap-2">
        <input type="radio" name="hopmode" value="all" bind:group={hopMode} />
        <span>Hop all</span>
      </label>
    </div>
    <div class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-3">
      {#if hopMode === 'lock'}
        <div class="md:col-span-1">
          <label class="block text-sm text-slate-600 mb-1">Lock to channel</label>
          <input class="border rounded px-2 py-1 w-full" type="number" bind:value={lockChan} min="1" />
        </div>
      {:else if hopMode === 'list'}
        <div class="md:col-span-2">
          <label class="block text-sm text-slate-600 mb-1">Channels (comma separated)</label>
          <input class="border rounded px-2 py-1 w-full" bind:value={hopListCsv} placeholder="e.g., 1,6,11,36,149" />
        </div>
      {/if}
      <div class="md:col-span-1">
        <label class="block text-sm text-slate-600 mb-1">Dwell (ms)</label>
        <input class="border rounded px-2 py-1 w-full" type="number" min="20" step="10" bind:value={dwellMs} />
      </div>
    </div>
    <div class="mt-4 flex flex-wrap gap-2">
      <button class="px-3 py-2 rounded bg-slate-900 text-white" on:click={async ()=>{ hopEnabled = true; await applyHop(); await refreshInfo(); }}>Apply</button>
      <button class="px-3 py-2 rounded bg-slate-900 text-white" on:click={makeMonitor}>Monitor + Up</button>
      <button class="px-3 py-2 rounded bg-emerald-700 text-white" on:click={createMonitorIface}>Create Monitor (safer)</button>
    </div>
  </div>

  <div class="text-xs text-slate-500 space-y-1">
    <div>Actions may require sudo permissions on the server; if denied, run: <code>python -m wids iface-up --dev {dev}</code></div>
    <div>Tip: Prefer <b>Create Monitor</b> to add a monitor vdev and avoid dropping connectivity or crashing the sniffer.</div>
    <div>Note: Changing hopping updates config and the hopper applies it live (no restart needed).</div>
  </div>

  {#if msg}<div class="text-green-700 text-sm">{msg}</div>{/if}
  {#if err}<div class="text-red-600 text-sm">{err}</div>{/if}
</div>

<style>
</style>
