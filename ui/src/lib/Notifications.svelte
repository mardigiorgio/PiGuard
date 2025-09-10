<script>
  import { onMount } from 'svelte'
  import { sse } from './api'

  let toasts = []
  let es

  function pushToast(a) {
    const id = Date.now() + Math.random()
    const t = {
      id,
      ts: a.ts || new Date().toISOString(),
      severity: a.severity || 'info',
      kind: a.kind || 'alert',
      summary: a.summary || '',
    }
    toasts = [t, ...toasts].slice(0, 6)
    setTimeout(() => dismiss(id), 8000)
  }

  function dismiss(id) {
    toasts = toasts.filter(t => t.id !== id)
  }

  onMount(() => {
    try {
      es = sse('/stream', (msg) => {
        if (msg && msg.kind) pushToast(msg)
      })
    } catch {}
    return () => { if (es) es.close() }
  })
</script>

<div class="fixed top-4 right-4 z-50 flex flex-col gap-2 w-[22rem] max-w-[90vw]">
  {#each toasts as t (t.id)}
    <div class="shadow-lg rounded border overflow-hidden bg-white">
      <div class="px-3 py-2 flex items-center gap-2 border-b">
        <span class="px-2 py-0.5 rounded text-white text-xs {t.severity==='critical' ? 'bg-red-600' : t.severity==='warn' ? 'bg-amber-500' : 'bg-slate-500'}">{t.severity}</span>
        <div class="font-semibold text-sm truncate">{t.kind}</div>
        <div class="ml-auto text-[10px] text-slate-500">{t.ts}</div>
        <button class="ml-2 text-slate-500 hover:text-slate-800" on:click={() => dismiss(t.id)} aria-label="Close">×</button>
      </div>
      <div class="px-3 py-2 text-sm">{t.summary}</div>
    </div>
  {/each}
 </div>

<style>
</style>

