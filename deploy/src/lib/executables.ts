import { spawnSync } from 'node:child_process'

export function requireExecutable(name: string): string {
  const cmd = process.platform === 'win32' ? 'where' : 'which'
  const result = spawnSync(cmd, [name], { encoding: 'utf8' })

  if (result.status !== 0 || !result.stdout.trim()) {
    console.error(`ERROR: '${name}' not found on PATH.`)
    process.exit(1)
  }

  return result.stdout.trim().split('\n')[0].trim()
}

export function spawnArgs(exe: string, args: string[]): [string, string[]] {
  if (process.platform === 'win32' && /\.(cmd|bat)$/i.test(exe)) {
    return ['cmd.exe', ['/c', exe, ...args]]
  }

  return [exe, args]
}

export const GCLOUD = requireExecutable('gcloud')
export const SSH_EXE = requireExecutable('ssh')
export const SCP_EXE = requireExecutable('scp')
export const SSH_KEYGEN = requireExecutable('ssh-keygen')
