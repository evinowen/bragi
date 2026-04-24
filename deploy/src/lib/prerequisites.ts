import { log } from './log'
import { config, vm } from './state'

export function checkPrerequisites(): void {
  log('Checking local prerequisites...')

  if (!config.projectId) {
    console.error('ERROR: gcp_project_id is not set in deploy.json.')
    process.exit(1)
  }

  log(`Project:      ${config.projectId}`)
  log(`Zone:         ${config.zone}`)
  log(`Machine type: ${config.machineType}`)
  log(`Instance:     ${vm.name}`)
  log(`Indexers:     ${config.indexers.length}`)
}
