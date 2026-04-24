import { spawnSync, SpawnSyncOptions } from 'node:child_process'

export function requireExecutable(name: string): string {
  const cmd = process.platform === 'win32' ? 'where' : 'which'
  const result = spawnSync(cmd, [name], { encoding: 'utf8' })

  if (result.status !== 0 || !result.stdout.trim()) {
    console.error(`ERROR: '${name}' not found on PATH.`)
    process.exit(1)
  }

  const lines = result.stdout.trim().split('\n').map(l => l.trim()).filter(Boolean)

  if (process.platform === 'win32') {
    const cmdLine = lines.find(l => /\.(cmd|bat)$/i.test(l))
    if (cmdLine) return cmdLine
  }

  return lines[0]
}

export function spawnArgs(exe: string, args: string[]): [string, string[], SpawnSyncOptions] {
  if (process.platform === 'win32' && /\.(cmd|bat)$/i.test(exe)) {
    const q = (s: string) => s.includes(' ') ? `"${s}"` : s
    const cmdLine = `"${[exe, ...args].map(s => q(s)).join(' ')}"`

    return ['cmd.exe', ['/d', '/s', '/c', cmdLine], { windowsVerbatimArguments: true }]
  }

  return [exe, args, {}]
}

export const GCLOUD = requireExecutable('gcloud')
export const SSH_EXE = requireExecutable('ssh')
export const SCP_EXE = requireExecutable('scp')
export const SSH_KEYGEN = requireExecutable('ssh-keygen')
