import * as fs from 'node:fs'
import { DISK_SIZE, IMAGE_FAMILY, IMAGE_PROJECT, NETWORK_TAG, SSH_USER } from './constants'
import { GCLOUD, SSH_KEYGEN } from './executables'
import { log } from './log'
import { run, runCapture, runOutput } from './run'
import { sshRun } from './ssh'
import { config, vm, work } from './state'

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

function generateSshKey(): void {
  log('Generating temporary SSH key pair...')
  run(SSH_KEYGEN, ['-t', 'rsa', '-b', '2048', '-f', work.sshKey, '-N', '', '-q'])
  log('SSH key generated')
}

function injectSshKey(): void {
  const pubKey = fs.readFileSync(`${work.sshKey}.pub`, 'utf8').trim()
  log('Injecting SSH public key into instance metadata...')
  run(GCLOUD, [
    'compute', 'instances', 'add-metadata', vm.name,
    `--zone=${config.zone}`, `--project=${config.projectId}`,
    `--metadata=ssh-keys=${SSH_USER}:${pubKey}`,
    '--quiet',
  ])
  log('SSH key injected')
}

export async function createInstance(): Promise<void> {
  log(`Creating Compute Engine instance: ${vm.name}`)
  const existing = runCapture(GCLOUD, [
    'compute', 'instances', 'describe', vm.name,
    `--zone=${config.zone}`, `--project=${config.projectId}`,
  ])

  if (existing.status !== 0) {
    run(GCLOUD, [
      'compute', 'instances', 'create', vm.name,
      `--project=${config.projectId}`, `--zone=${config.zone}`,
      `--machine-type=${config.machineType}`,
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

  vm.created = true
  vm.ip = runOutput(GCLOUD, [
    'compute', 'instances', 'describe', vm.name,
    `--zone=${config.zone}`, `--project=${config.projectId}`,
    '--format=get(networkInterfaces[0].accessConfigs[0].natIP)',
  ])
  log('Instance created:')
  log(`  Name:       ${vm.name}`)
  log(`  Public IP:  ${vm.ip}`)
  log(`  Zone:       ${config.zone}`)
  log(`  Machine:    ${config.machineType}`)

  generateSshKey()
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
