<script>
  import { onMount } from 'svelte'
  import { getLogs, postAdminClear } from '../lib/api'

  let items = []
  let sinceId = null
  let paused = false
  let source = '' // '', 'sniffer', 'sensor', 'api'
  let err = ''
  let msg = ''
  let timer

  function reset() {
    items = []
    sinceId = null
  }

  async function poll() {
    if (paused) return
    try {
      const next = await getLogs({ since_id: sinceId, limit: sinceId ? 500 : 200, source })
      if (next && next.length) {
        // when sinceId null, backend returns newest first; reverse to append oldest->newest
        const list = sinceId ? next : next.slice().reverse()
        items = items.concat(list)
        if (items.length > 2000) items = items.slice(-2000)
        sinceId = items[items.length - 1].id
      }
      err = ''
      msg = ''
    } catch (e) {
      err = e.message
    }
  }

  onMount(() => {
    poll()
    timer = setInterval(poll, 1500)
    return () => clearInterval(timer)
  })
</script>

<div class="space-y-3">
  <div class="flex items-center gap-2">
    <label class="text-sm text-slate-600">Source</label>
    <select class="border rounded px-2 py-1 text-sm" bind:value={source} on:change={() => { reset(); poll() }}>
      <option value="">All</option>
      <option value="sniffer">Sniffer</option>
      <option value="sensor">Sensor</option>
      <option value="api">API</option>
    </select>
    <button class="px-2 py-1 border rounded text-sm" on:click={() => paused = !paused}>{paused ? 'Resume' : 'Pause'}</button>
    <button class="px-2 py-1 border rounded text-sm" on:click={() => { reset(); poll() }}>Clear</button>
    <span class="text-xs text-slate-500">{items.length} lines</span>
  </div>

  <div class="mt-2 p-3 border rounded bg-red-50">
    <div class="text-sm font-semibold text-red-700 mb-1">Danger zone</div>
    <div class="flex flex-wrap gap-2 items-center">
      <button class="px-2 py-1 rounded bg-red-600 text-white text-sm" on:click={async () => {
        if (!confirm('Clear ALL events and alerts?')) return
        try {
          await postAdminClear(['events','alerts'])
          msg = 'Cleared events and alerts.'; err=''
        } catch (e) { err = e.message; msg='' }
      }}>Clear Alerts + Events</button>
      <button class="px-2 py-1 rounded border text-sm" on:click={async () => {
        if (!confirm('Clear logs table?')) return
        try {
          await postAdminClear(['logs'])
          reset(); msg = 'Cleared logs.'; err=''
        } catch (e) { err = e.message; msg='' }
      }}>Clear Logs</button>
      {#if msg}<span class="text-green-700 text-xs">{msg}</span>{/if}
      {#if err}<span class="text-red-600 text-xs">{err}</span>{/if}
    </div>
  </div>

  {#if err}
    <div class="text-red-600 text-sm">{err}</div>
  {/if}

  <div class="border rounded max-h-[60vh] overflow-auto">
    <table class="w-full text-sm">
      <thead class="bg-slate-50 text-slate-600">
        <tr>
          <th class="text-left px-2 py-1 w-40">Time</th>
          <th class="text-left px-2 py-1 w-20">Source</th>
          <th class="text-left px-2 py-1 w-16">Level</th>
          <th class="text-left px-2 py-1">Message</th>
        </tr>
      </thead>
      <tbody>
        {#each items as r}
          <tr class="border-t">
            <td class="px-2 py-1 whitespace-nowrap">{r.ts?.replace('T',' ').replace('Z','')}</td>
            <td class="px-2 py-1">{r.source}</td>
            <td class="px-2 py-1">
              <span class="px-2 py-0.5 rounded text-white text-xs {r.level==='error' ? 'bg-red-600' : r.level==='warn' ? 'bg-amber-500' : 'bg-slate-500'}">{r.level}</span>
            </td>
            <td class="px-2 py-1 font-mono text-xs">{r.message}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>

<style>
</style>
