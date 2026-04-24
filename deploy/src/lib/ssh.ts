import { spawnSync, SpawnSyncOptions, SpawnSyncReturns } from 'node:child_process'
import { SSH_USER } from './constants'
import { SCP_EXE, SSH_EXE, spawnArgs } from './executables'
import { run } from './run'
import { vm, work } from './state'

export function sshRun(args: string[], opts: SpawnSyncOptions = {}): { status: number, stdout: string, stderr: string } {
  const base = [
    '-i', work.sshKey,
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'ConnectTimeout=30',
    '-o', 'BatchMode=yes',
    `${SSH_USER}@${vm.ip}`,
  ]
  const [resolvedCmd, resolvedArgs] = spawnArgs(SSH_EXE, [...base, ...args])
  const result = spawnSync(resolvedCmd, resolvedArgs, { encoding: 'utf8', ...opts }) as SpawnSyncReturns<string>

  return {
    status: result.status ?? 1,
    stdout: typeof result.stdout === 'string' ? result.stdout : '',
    stderr: typeof result.stderr === 'string' ? result.stderr : '',
  }
}

export function scpTo(localPath: string, remotePath: string): void {
  run(SCP_EXE, [
    '-i', work.sshKey,
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'BatchMode=yes',
    localPath,
    `${SSH_USER}@${vm.ip}:${remotePath}`,
  ])
}
