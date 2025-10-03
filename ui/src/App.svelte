<script>
  import { onMount } from 'svelte'
  import Overview from './routes/Overview.svelte'
  import Alerts from './routes/Alerts.svelte'
  import Defense from './routes/Defense.svelte'
  import Device from './routes/Device.svelte'
  import Logs from './routes/Logs.svelte'
  import Settings from './routes/Settings.svelte'
  import Login from './routes/Login.svelte'
  import Notifications from './lib/Notifications.svelte'
  import { isAuthenticated, logout, getUsername } from './lib/api'

  let authenticated = isAuthenticated()
  let username = getUsername()
  let tab = 'overview'
  const tabs = [
    { id: 'overview', label: 'Overview', comp: Overview },
    { id: 'alerts', label: 'Alerts', comp: Alerts },
    { id: 'defense', label: 'Defense', comp: Defense },
    { id: 'device', label: 'Device', comp: Device },
    { id: 'settings', label: 'Settings', comp: Settings },
    { id: 'logs', label: 'Logs', comp: Logs },
  ]

  async function handleLogout() {
    await logout()
    authenticated = false
    username = null
  }
</script>

{#if !authenticated}
  <Login />
{:else}
  <div class="max-w-5xl mx-auto p-4 relative">
    <div class="flex justify-between items-center mb-4">
      <h1 class="text-2xl font-bold">PiGuard</h1>
      <div class="flex items-center gap-4">
        <span class="text-sm text-slate-600">Welcome, {username || 'User'}</span>
        <button class="text-sm text-slate-600 hover:text-slate-900 underline" on:click={handleLogout}>
          Logout
        </button>
      </div>
    </div>
    <nav class="flex gap-2 mb-4">
      {#each tabs as t}
        <button class="px-3 py-2 rounded border text-sm bg-white hover:bg-slate-100 {tab===t.id ? 'border-slate-900' : 'border-slate-300'}" on:click={() => tab = t.id}>
          {t.label}
        </button>
      {/each}
    </nav>
    <div class="bg-white border border-slate-200 rounded p-4">
      {#if tab === 'overview'}
        <Overview />
      {:else if tab === 'alerts'}
        <Alerts />
      {:else if tab === 'defense'}
        <Defense />
      {:else if tab === 'device'}
        <Device />
      {:else if tab === 'settings'}
        <Settings />
      {:else}
        <Logs />
      {/if}
    </div>
    <Notifications />
  </div>
{/if}

<style>
</style>
