
<script>
  import { onMount } from 'svelte'
  import { getDefense, postDefense, getSSIDs } from '../lib/api'
  let defense = { ssid: '', allowed_bssids: [], allowed_channels: [], allowed_bands: [] }
  let ssids = []
  let msg = ''
  let err = ''
  // Local CSV mirrors for inputs
  let allowedBssidsCsv = ''
  let allowedChannelsCsv = ''
  let allowedBandsCsv = ''

  async function load() {
    try { defense = await getDefense() } catch {}
    try { ssids = await getSSIDs() } catch {}
    // Initialize CSV from defense
    allowedBssidsCsv = (defense.allowed_bssids || []).join(',')
    allowedChannelsCsv = (defense.allowed_channels || []).join(',')
    allowedBandsCsv = (defense.allowed_bands || []).join(',')
  }
  onMount(load)

  async function save() {
    err = msg = ''
    try {
      const body = { ...defense }
      // Normalize types
      body.allowed_bssids = (body.allowed_bssids || []).map(x => String(x).trim()).filter(Boolean)
      body.allowed_channels = (body.allowed_channels || []).map(x => parseInt(x)).filter(x => !isNaN(x))
      body.allowed_bands = (body.allowed_bands || []).map(x => String(x))
      await postDefense(body)
      msg = 'Saved. Sensor may require restart to reload config.'
    } catch (e) {
      err = e.message
    }
  }
</script>

<div class="space-y-4">
  <div>
    <label class="block text-sm text-slate-600 mb-1">Defended SSID</label>
    <select class="border rounded px-2 py-1 w-full" bind:value={defense.ssid}>
      <option value="">-- Not armed --</option>
      {#each ssids as s}
        <option value={s.ssid}>{s.ssid}</option>
      {/each}
      {#if defense.ssid && !ssids.some(s => s.ssid === defense.ssid)}
        <option value={defense.ssid}>(current) {defense.ssid}</option>
      {/if}
    </select>
  </div>

  <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
    <div>
      <label class="block text-sm text-slate-600 mb-1">Allowed BSSIDs (comma separated)</label>
      <input class="border rounded px-2 py-1 w-full" bind:value={allowedBssidsCsv} on:change={() => {
        defense.allowed_bssids = allowedBssidsCsv.split(',').map(x=>x.trim()).filter(Boolean)
      }} />
    </div>
    <div>
      <label class="block text-sm text-slate-600 mb-1">Allowed Channels (comma separated)</label>
      <input class="border rounded px-2 py-1 w-full" bind:value={allowedChannelsCsv} on:change={() => {
        defense.allowed_channels = allowedChannelsCsv.split(',')
          .map(x=>parseInt(x))
          .filter(x=>!isNaN(x))
      }} />
    </div>
    <div>
      <label class="block text-sm text-slate-600 mb-1">Allowed Bands (comma separated, e.g., 2.4,5,6)</label>
      <input class="border rounded px-2 py-1 w-full" bind:value={allowedBandsCsv} on:change={() => {
        defense.allowed_bands = allowedBandsCsv.split(',').map(x=>x.trim()).filter(Boolean)
      }} />
    </div>
  </div>

  <div class="flex gap-2 items-center">
    <button class="px-3 py-2 rounded bg-slate-900 text-white" on:click={save}>Save</button>
    {#if msg}<span class="text-green-700 text-sm">{msg}</span>{/if}
    {#if err}<span class="text-red-600 text-sm">{err}</span>{/if}
  </div>

  <div>
    <h3 class="font-semibold mb-1">Observed SSIDs (last 10 min)</h3>
    <ul class="text-sm list-disc ml-5">
      {#each ssids as s}
        <li>{s.ssid} — BSSIDs: {s.bssids.join(', ')}; Channels: {s.channels.join(', ')}</li>
      {/each}
    </ul>
    {#if ssids.length === 0}
      <div class="text-slate-500 text-sm">No beacons observed yet.</div>
    {/if}
  </div>
</div>
