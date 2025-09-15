<script>
  import { onMount } from 'svelte'
  import { getDeauthSettings, postDeauthSettings } from '../lib/api'

  let deauth = { window_sec: 10, per_src_limit: 30, global_limit: 80, cooldown_sec: 60 }
  let msg = ''
  let err = ''

  async function load() {
    try { deauth = await getDeauthSettings() } catch(e) { err = e.message }
  }
  onMount(load)

  async function save() {
    err = msg = ''
    try {
      const body = {
        window_sec: parseInt(deauth.window_sec),
        per_src_limit: parseInt(deauth.per_src_limit),
        global_limit: parseInt(deauth.global_limit),
        cooldown_sec: parseInt(deauth.cooldown_sec),
      }
      await postDeauthSettings(body)
      msg = 'Saved. Sensor will use new thresholds on next loop tick.'
    } catch (e) {
      err = e.message
    }
  }
</script>

<div class="space-y-4">
  <div>
    <h2 class="text-lg font-semibold">Deauth Detection</h2>
    <p class="text-sm text-slate-600">Tune thresholds used by the sensor for deauthentication burst detection.</p>
  </div>

  <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
    <div>
      <label class="block text-sm text-slate-600 mb-1">Window (sec)</label>
      <input class="border rounded px-2 py-1 w-full" type="number" min="1" bind:value={deauth.window_sec} />
    </div>
    <div>
      <label class="block text-sm text-slate-600 mb-1">Per-source limit</label>
      <input class="border rounded px-2 py-1 w-full" type="number" min="1" bind:value={deauth.per_src_limit} />
    </div>
    <div>
      <label class="block text-sm text-slate-600 mb-1">Global limit</label>
      <input class="border rounded px-2 py-1 w-full" type="number" min="1" bind:value={deauth.global_limit} />
    </div>
    <div>
      <label class="block text-sm text-slate-600 mb-1">Cooldown (sec)</label>
      <input class="border rounded px-2 py-1 w-full" type="number" min="1" bind:value={deauth.cooldown_sec} />
    </div>
  </div>

  <div class="flex gap-2 items-center">
    <button class="px-3 py-2 rounded bg-slate-900 text-white" on:click={save}>Save</button>
    {#if msg}<span class="text-green-700 text-sm">{msg}</span>{/if}
    {#if err}<span class="text-red-600 text-sm">{err}</span>{/if}
  </div>
</div>

<style>
</style>

