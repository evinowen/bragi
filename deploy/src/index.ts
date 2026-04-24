#!/usr/bin/env tsx
/**
 * Bragi deployment script — provisions a GCP VM, installs bragi, and verifies all services.
 */

import * as fs from 'node:fs'
import * as os from 'node:os'
import path from 'node:path'
import { spawnSync, SpawnSyncOptions, SpawnSyncReturns } from 'node:child_process'

// ── Constants ─────────────────────────────────────────────────────────────────

const DEPLOY_DIR = path.join(__dirname, '..')
const SCRIPTS_DIR = path.join(DEPLOY_DIR, 'scripts')
const CONFIG_FILE = path.join(DEPLOY_DIR, 'deploy.json')

const IMAGE_FAMILY = 'ubuntu-2204-lts'
const IMAGE_PROJECT = 'ubuntu-os-cloud'
const DISK_SIZE = '30GB'
const NETWORK_TAG = 'bragi-test'
const SSH_USER = 'bragi'

// ── Executable resolution ─────────────────────────────────────────────────────

function requireExecutable(name: string): string {
  const cmd = process.platform === 'win32' ? 'where' : 'which'
  const result = spawnSync(cmd, [name], { encoding: 'utf8' })
  if (result.status !== 0 || !result.stdout.trim()) {
    console.error(`ERROR: '${name}' not found on PATH.`)
    process.exit(1)
  }

  return result.stdout.trim().split('\n')[0].trim()
}

function spawnArgs(exe: string, args: string[]): [string, string[]] {
  if (process.platform === 'win32' && /\.(cmd|bat)$/i.test(exe)) {
    return ['cmd.exe', ['/c', exe, ...args]]
  }

  return [exe, args]
}

const GCLOUD = requireExecutable('gcloud')
const SSH_EXE = requireExecutable('ssh')
const SCP_EXE = requireExecutable('scp')
const SSH_KEYGEN = requireExecutable('ssh-keygen')

// ── Colors ────────────────────────────────────────────────────────────────────

const RED = '\u001B[0;31m'
const GREEN = '\u001B[0;32m'
const YELLOW = '\u001B[1;33m'
const CYAN = '\u001B[0;36m'
const NC = '\u001B[0m'

// ── State ─────────────────────────────────────────────────────────────────────

let passCount = 0
let failCount = 0
let instanceCreated = false
const instanceName = `bragi-test-${Math.floor(Date.now() / 1000)}`
let instanceIp = ''
const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bragi-deploy-'))
const sshKey = path.join(workDir, 'id_rsa')

// ── Config types ──────────────────────────────────────────────────────────────

interface Indexer {
  name: string
  url: string
  api_key?: string
  api_path?: string
  television?: boolean
  movies?: boolean
  categories?: number[]
  anime_categories?: number[]
}

interface Config {
  gcp_project_id?: string
  gcp_zone?: string
  gcp_machine_type?: string
  skip_cleanup?: boolean
  setup_firewall?: boolean
  sabnzbd?: { max_download_speed?: string }
  usenet?: {
    host?: string
    username?: string
    password?: string
    ssl?: boolean
  }
  indexers?: Indexer[]
}

// ── Config state ──────────────────────────────────────────────────────────────

let projectId = ''
let zone = ''
let machineType = 'e2-standard-2'
let skipCleanup = false
let doFirewall = false
let usenetHost = ''
let usenetUser = ''
let usenetPass = ''
let usenetSsl = true
let indexers: Indexer[] = []
let sabnzbdMaxSpeed = ''

// ── Logging ───────────────────────────────────────────────────────────────────

function log(msg: string): void {
  console.log(`${CYAN}[DEPLOY]${NC}  ${msg}`)
}

function logWarn(msg: string): void {
  console.log(`${YELLOW}[WARN]${NC}  ${msg}`)
}

function logSuccess(msg: string): void {
  passCount++
  console.log(`${GREEN}[PASS]${NC}  ${msg}`)
}

function logFailure(msg: string): void {
  failCount++
  console.log(`${RED}[FAIL]${NC}  ${msg}`)
}

// ── Subprocess helpers ────────────────────────────────────────────────────────

function run(cmd: string, args: string[], opts: SpawnSyncOptions = {}): void {
  const [resolvedCmd, resolvedArgs] = spawnArgs(cmd, args)
  const result = spawnSync(resolvedCmd, resolvedArgs, { stdio: 'inherit', ...opts })
  if (result.status !== 0) {
    process.exit(result.status ?? 1)
  }
}

function runOutput(cmd: string, args: string[]): string {
  const [resolvedCmd, resolvedArgs] = spawnArgs(cmd, args)
  const result = spawnSync(resolvedCmd, resolvedArgs, { encoding: 'utf8' })
  if (result.status !== 0) {
    console.error(result.stderr)
    process.exit(result.status ?? 1)
  }

  return (result.stdout).trim()
}

function runCapture(cmd: string, args: string[]): { status: number, stdout: string, stderr: string } {
  const [resolvedCmd, resolvedArgs] = spawnArgs(cmd, args)
  const result: SpawnSyncReturns<string> = spawnSync(resolvedCmd, resolvedArgs, { encoding: 'utf8' })
  return {
    status: result.status ?? 1,
    stdout: result.stdout,
    stderr: result.stderr,
  }
}

function sshRun(args: string[], opts: SpawnSyncOptions = {}): { status: number, stdout: string, stderr: string } {
  const base = [
    '-i', sshKey,
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'ConnectTimeout=30',
    '-o', 'BatchMode=yes',
    `${SSH_USER}@${instanceIp}`,
  ]
  const [resolvedCmd, resolvedArgs] = spawnArgs(SSH_EXE, [...base, ...args])
  const result = spawnSync(resolvedCmd, resolvedArgs, { encoding: 'utf8', ...opts }) as SpawnSyncReturns<string>
  return {
    status: result.status ?? 1,
    stdout: typeof result.stdout === 'string' ? result.stdout : '',
    stderr: typeof result.stderr === 'string' ? result.stderr : '',
  }
}

function scpTo(localPath: string, remotePath: string): void {
  run(SCP_EXE, [
    '-i', sshKey,
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'BatchMode=yes',
    localPath,
    `${SSH_USER}@${instanceIp}:${remotePath}`,
  ])
}

// ── Config loading ────────────────────────────────────────────────────────────

function loadConfig(): void {
  if (!fs.existsSync(CONFIG_FILE)) {
    console.error(`ERROR: ${CONFIG_FILE} not found.`)
    process.exit(1)
  }

  const cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')) as Config

  projectId = cfg.gcp_project_id ?? ''
  zone = cfg.gcp_zone ?? ''
  machineType = cfg.gcp_machine_type ?? 'e2-standard-2'
  skipCleanup = cfg.skip_cleanup ?? false
  doFirewall = cfg.setup_firewall ?? false

  usenetHost = cfg.usenet?.host ?? ''
  usenetUser = cfg.usenet?.username ?? ''
  usenetPass = cfg.usenet?.password ?? ''
  usenetSsl = cfg.usenet?.ssl ?? true

  indexers = cfg.indexers ?? []
  sabnzbdMaxSpeed = cfg.sabnzbd?.max_download_speed ?? ''
}

// ── Cleanup ───────────────────────────────────────────────────────────────────

function cleanup(): void {
  try {
    fs.rmSync(workDir, { recursive: true, force: true })
  }
  catch { /* ignore */ }

  if (instanceCreated) {
    if (skipCleanup) {
      logWarn(`skip_cleanup=true — instance '${instanceName}' left running in zone ${zone}`)
      logWarn('Delete it with:')
      logWarn(`  gcloud compute instances delete ${instanceName} --zone=${zone} --project=${projectId}`)
    }
    else {
      log(`Deleting instance: ${instanceName}`)
      runCapture(GCLOUD, [
        'compute', 'instances', 'delete', instanceName,
        `--zone=${zone}`, `--project=${projectId}`, '--quiet',
      ])
      log('Instance deleted')
    }
  }
}

process.on('exit', cleanup)

// ── Prerequisites ─────────────────────────────────────────────────────────────

function checkPrerequisites(): void {
  log('Checking local prerequisites...')
  if (!projectId) {
    console.error('ERROR: gcp_project_id is not set in deploy.json.')
    process.exit(1)
  }

  log(`Project:      ${projectId}`)
  log(`Zone:         ${zone}`)
  log(`Machine type: ${machineType}`)
  log(`Instance:     ${instanceName}`)
  log(`Indexers:     ${indexers.length}`)
}

// ── Firewall ──────────────────────────────────────────────────────────────────

function ensureFirewallRule(name: string, ports: string): void {
  const result = runCapture(GCLOUD, [
    'compute', 'firewall-rules', 'describe', name, `--project=${projectId}`,
  ])
  if (result.status === 0) {
    log(`Firewall rule '${name}' already exists, skipping`)
    return
  }

  log(`Creating firewall rule '${name}' (${ports})...`)
  run(GCLOUD, [
    'compute', 'firewall-rules', 'create', name,
    `--project=${projectId}`,
    '--direction=INGRESS', '--action=ALLOW',
    `--rules=${ports}`,
    '--source-ranges=0.0.0.0/0',
    `--target-tags=${NETWORK_TAG}`,
    '--quiet',
  ])
  log(`Firewall rule '${name}' created`)
}

function setupFirewall(): void {
  if (!doFirewall) return
  ensureFirewallRule('bragi-test-ssh', 'tcp:22')
  ensureFirewallRule('bragi-test-services', 'tcp:8080,tcp:8989,tcp:7878')
  ensureFirewallRule('bragi-test-http', 'tcp:80')
}

// ── SSH key ───────────────────────────────────────────────────────────────────

function generateSshKey(): void {
  log('Generating temporary SSH key pair...')
  run(SSH_KEYGEN, ['-t', 'rsa', '-b', '2048', '-f', sshKey, '-N', '', '-q'])
  log('SSH key generated')
}

function injectSshKey(): void {
  const pubKey = fs.readFileSync(`${sshKey}.pub`, 'utf8').trim()
  log('Injecting SSH public key into instance metadata...')
  run(GCLOUD, [
    'compute', 'instances', 'add-metadata', instanceName,
    `--zone=${zone}`, `--project=${projectId}`,
    `--metadata=ssh-keys=${SSH_USER}:${pubKey}`,
    '--quiet',
  ])
  log('SSH key injected')
}

// ── Instance ──────────────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function createInstance(): Promise<void> {
  log(`Creating Compute Engine instance: ${instanceName}`)
  const existing = runCapture(GCLOUD, [
    'compute', 'instances', 'describe', instanceName,
    `--zone=${zone}`, `--project=${projectId}`,
  ])
  if (existing.status !== 0) {
    run(GCLOUD, [
      'compute', 'instances', 'create', instanceName,
      `--project=${projectId}`, `--zone=${zone}`,
      `--machine-type=${machineType}`,
      `--image-family=${IMAGE_FAMILY}`,
      `--image-project=${IMAGE_PROJECT}`,
      `--boot-disk-size=${DISK_SIZE}`,
      '--boot-disk-type=pd-standard',
      '--network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY',
      '--scopes=cloud-platform',
      `--tags=${NETWORK_TAG}`,
      '--metadata=enable-oslogin=false',
      '--quiet',
    ])
  }

  instanceCreated = true
  instanceIp = runOutput(GCLOUD, [
    'compute', 'instances', 'describe', instanceName,
    `--zone=${zone}`, `--project=${projectId}`,
    '--format=get(networkInterfaces[0].accessConfigs[0].natIP)',
  ])
  log('Instance created:')
  log(`  Name:       ${instanceName}`)
  log(`  Public IP:  ${instanceIp}`)
  log(`  Zone:       ${zone}`)
  log(`  Machine:    ${machineType}`)

  injectSshKey()
  log('Waiting for SSH to become available...')
  for (let attempt = 1; attempt <= 24; attempt++) {
    if (sshRun(['echo', 'ssh-ready'], { stdio: 'pipe' }).status === 0) break
    log(`SSH not yet ready (attempt ${attempt}/24)...`)
    await sleep(10_000)
    if (attempt === 24) {
      console.error('ERROR: SSH not available after 240 seconds')
      process.exit(1)
    }
  }

  log('SSH is ready')
  log('Waiting for cloud-init to complete...')
  sshRun(['cloud-init', 'status', '--wait'], { stdio: 'pipe' })
  log('Instance is ready')
}

// ── Helper scripts ────────────────────────────────────────────────────────────

function script(name: string): string {
  return fs.readFileSync(path.join(SCRIPTS_DIR, name), 'utf8')
}

function writeScript(filePath: string, content: string): void {
  fs.writeFileSync(filePath, content, { encoding: 'utf8' })
}

function writeScripts(): void {
  writeScript(path.join(workDir, 'setup.sh'), script('setup.sh'))

  const indexersB64 = Buffer.from(JSON.stringify(indexers)).toString('base64')
  const sslResponse = usenetSsl ? '' : 'n'
  const runInstall = script('run_install.sh')
    .replace('__INDEXERS_B64__', () => indexersB64)
    .replace('__USENET_HOST__', () => usenetHost)
    .replace('__USENET_USER__', () => usenetUser)
    .replace('__USENET_PASS__', () => usenetPass)
    .replace('__SSL_RESPONSE__', () => sslResponse)
    .replace('__SABNZBD_MAX_SPEED__', () => sabnzbdMaxSpeed)
  writeScript(path.join(workDir, 'run_install.sh'), runInstall)

  writeScript(path.join(workDir, 'verify.sh'), script('verify.sh'))
}

// ── Phases ────────────────────────────────────────────────────────────────────

function installDependencies(): void {
  log('Installing Docker, git, and expect on the instance...')
  scpTo(path.join(workDir, 'setup.sh'), '/tmp/setup.sh')
  sshRun(['sudo', 'bash', '/tmp/setup.sh'], { stdio: 'inherit' })
  log('Dependencies installed')
}

function runInstaller(): void {
  log('Running bragi installer (this may take several minutes while images pull)...')
  scpTo(path.join(workDir, 'run_install.sh'), '/tmp/run_install.sh')
  sshRun(['sudo', 'bash', '/tmp/run_install.sh'], { stdio: 'inherit' })
  log('Installer finished')
}

function verifyInstallation(): void {
  log('Verifying installation...')
  scpTo(path.join(workDir, 'verify.sh'), '/tmp/verify.sh')
  const result = sshRun(['sudo', 'bash', '/tmp/verify.sh'], { stdio: 'pipe' })
  for (const line of result.stdout.split('\n')) {
    if (!line.trim()) continue
    console.log(line)
    if (line.startsWith('PASS: ')) logSuccess(line.slice(6))
    else if (line.startsWith('FAIL: ')) logFailure(line.slice(6))
  }
}

function reportResults(): void {
  console.log()
  console.log('========================================')
  console.log('          Test Results Summary')
  console.log('========================================')
  console.log(`  ${GREEN}Passed: ${passCount}${NC}`)
  console.log(`  ${RED}Failed: ${failCount}${NC}`)
  console.log('========================================')

  if (failCount === 0) {
    console.log(`\n${GREEN}All tests passed — bragi installed successfully.${NC}\n`)
    console.log('=== Service Web Interfaces ===')
    console.log(`  SABnzbd:  http://${instanceIp}/sabnzbd`)
    console.log(`  Sonarr:   http://${instanceIp}/sonarr`)
    console.log(`  Radarr:   http://${instanceIp}/radarr`)
    console.log()
    process.exit(0)
  }
  else {
    console.log(`\n${RED}${failCount} test(s) failed. Review output above for details.${NC}\n`)
    process.exit(1)
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  loadConfig()
  checkPrerequisites()
  setupFirewall()
  generateSshKey()
  writeScripts()
  await createInstance()
  installDependencies()
  runInstaller()
  verifyInstallation()
  reportResults()
}

main().catch((error: unknown) => {
  console.error(error)
  process.exit(1)
})
