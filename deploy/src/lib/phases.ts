import path from 'node:path'
import { log, logFailure, logSuccess } from './log'
import { scpTo, sshRun } from './ssh'
import { work } from './state'

export function installDependencies(): void {
  log('Installing Docker, git, and expect on the instance...')
  scpTo(path.join(work.dir, 'setup.sh'), '/tmp/setup.sh')
  sshRun(['sudo', 'bash', '/tmp/setup.sh'], { stdio: 'inherit' })
  log('Dependencies installed')
}

export function runInstaller(): void {
  log('Running bragi installer (this may take several minutes while images pull)...')
  scpTo(path.join(work.dir, 'run_install.sh'), '/tmp/run_install.sh')
  sshRun(['sudo', 'bash', '/tmp/run_install.sh'], { stdio: 'inherit' })
  log('Installer finished')
}

export function verifyInstallation(): void {
  log('Verifying installation...')
  scpTo(path.join(work.dir, 'verify.sh'), '/tmp/verify.sh')
  const result = sshRun(['sudo', 'bash', '/tmp/verify.sh'], { stdio: 'pipe' })

  for (const line of result.stdout.split('\n')) {
    if (!line.trim()) continue
    console.log(line)
    if (line.startsWith('PASS: ')) logSuccess(line.slice(6))
    else if (line.startsWith('FAIL: ')) logFailure(line.slice(6))
  }
}
