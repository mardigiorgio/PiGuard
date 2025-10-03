<script>
  import { login } from '../lib/api'

  let username = ''
  let password = ''
  let error = ''
  let loading = false

  async function handleLogin() {
    error = ''
    loading = true
    try {
      await login(username, password)
      // Trigger a custom event or reload to notify parent
      window.location.reload()
    } catch (e) {
      error = e.message || 'Login failed. Please check your credentials.'
    } finally {
      loading = false
    }
  }

  function handleSubmit(e) {
    e.preventDefault()
    handleLogin()
  }
</script>

<div class="min-h-screen flex items-center justify-center bg-slate-50">
  <div class="max-w-md w-full space-y-8 p-8 bg-white rounded-lg shadow-md">
    <div>
      <h1 class="text-3xl font-bold text-center text-slate-900">PiGuard</h1>
      <h2 class="mt-2 text-center text-sm text-slate-600">Wi-Fi Intrusion Detection System</h2>
      <p class="mt-4 text-center text-sm text-slate-500">Sign in to access the dashboard</p>
    </div>

    <form class="mt-8 space-y-6" on:submit={handleSubmit}>
      <div class="space-y-4">
        <div>
          <label for="username" class="block text-sm font-medium text-slate-700">Username</label>
          <input
            id="username"
            name="username"
            type="text"
            required
            bind:value={username}
            disabled={loading}
            class="mt-1 block w-full px-3 py-2 border border-slate-300 rounded-md shadow-sm focus:outline-none focus:ring-slate-500 focus:border-slate-500"
            placeholder="admin"
          />
        </div>

        <div>
          <label for="password" class="block text-sm font-medium text-slate-700">Password</label>
          <input
            id="password"
            name="password"
            type="password"
            required
            bind:value={password}
            disabled={loading}
            class="mt-1 block w-full px-3 py-2 border border-slate-300 rounded-md shadow-sm focus:outline-none focus:ring-slate-500 focus:border-slate-500"
            placeholder="Enter your password"
          />
        </div>
      </div>

      {#if error}
        <div class="rounded-md bg-red-50 p-4">
          <p class="text-sm text-red-800">{error}</p>
        </div>
      {/if}

      <div>
        <button
          type="submit"
          disabled={loading}
          class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-slate-900 hover:bg-slate-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-slate-500 disabled:bg-slate-400 disabled:cursor-not-allowed"
        >
          {loading ? 'Signing in...' : 'Sign in'}
        </button>
      </div>
    </form>

    <div class="text-center text-xs text-slate-500 mt-4">
      <p>Default credentials are in your config file</p>
      <p class="mt-1">(/etc/piguard/wids.yaml)</p>
    </div>
  </div>
</div>

<style>
</style>
