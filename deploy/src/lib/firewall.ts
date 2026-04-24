import { NETWORK_TAG } from './constants'
import { GCLOUD } from './executables'
import { log } from './log'
import { run, runCapture } from './run'
import { config } from './state'

function ensureFirewallRule(name: string, ports: string): void {
  const result = runCapture(GCLOUD, [
    'compute', 'firewall-rules', 'describe', name, `--project=${config.projectId}`,
  ])

  if (result.status === 0) {
    log(`Firewall rule '${name}' already exists, skipping`)
    return
  }

  log(`Creating firewall rule '${name}' (${ports})...`)
  run(GCLOUD, [
    'compute', 'firewall-rules', 'create', name,
    `--project=${config.projectId}`,
    '--direction=INGRESS', '--action=ALLOW',
    `--rules=${ports}`,
    '--source-ranges=0.0.0.0/0',
    `--target-tags=${NETWORK_TAG}`,
    '--quiet',
  ])
  log(`Firewall rule '${name}' created`)
}

export function setupFirewall(): void {
  if (!config.doFirewall) return

  ensureFirewallRule('bragi-test-ssh', 'tcp:22')
  ensureFirewallRule('bragi-test-services', 'tcp:8080,tcp:8989,tcp:7878')
  ensureFirewallRule('bragi-test-http', 'tcp:80')
}
