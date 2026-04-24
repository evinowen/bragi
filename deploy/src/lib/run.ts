import { spawnSync, SpawnSyncOptions, SpawnSyncReturns } from 'node:child_process'
import { spawnArgs } from './executables'

export function run(cmd: string, args: string[], opts: SpawnSyncOptions = {}): void {
  const [resolvedCmd, resolvedArgs, resolvedOpts] = spawnArgs(cmd, args)
  const result = spawnSync(resolvedCmd, resolvedArgs, { stdio: 'inherit', ...resolvedOpts, ...opts })

  if (result.status !== 0) {
    process.exit(result.status ?? 1)
  }
}

export function runOutput(cmd: string, args: string[]): string {
  const [resolvedCmd, resolvedArgs, resolvedOpts] = spawnArgs(cmd, args)
  const result = spawnSync(resolvedCmd, resolvedArgs, { encoding: 'utf8', ...resolvedOpts }) as SpawnSyncReturns<string>

  if (result.status !== 0) {
    console.error(result.stderr)
    process.exit(result.status ?? 1)
  }

  return result.stdout.trim()
}

export function runCapture(cmd: string, args: string[]): { status: number, stdout: string, stderr: string } {
  const [resolvedCmd, resolvedArgs, resolvedOpts] = spawnArgs(cmd, args)
  const result = spawnSync(resolvedCmd, resolvedArgs, { encoding: 'utf8', ...resolvedOpts }) as SpawnSyncReturns<string>

  return {
    status: result.status ?? 1,
    stdout: result.stdout,
    stderr: result.stderr,
  }
}
