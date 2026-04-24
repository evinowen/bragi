import * as fs from 'node:fs'
import { GCLOUD } from './executables'
import { log, logWarn } from './log'
import { runCapture } from './run'
import { config, vm, work } from './state'

export function cleanup(): void {
  try {
    fs.rmSync(work.dir, { recursive: true, force: true })
  }
  catch { /* ignore */ }

  if (vm.created) {
    if (config.skipCleanup) {
      logWarn(`skip_cleanup=true — instance '${vm.name}' left running in zone ${config.zone}`)
      logWarn('Delete it with:')
      logWarn(`  gcloud compute instances delete ${vm.name} --zone=${config.zone} --project=${config.projectId}`)
    }
    else {
      log(`Deleting instance: ${vm.name}`)
      runCapture(GCLOUD, [
        'compute', 'instances', 'delete', vm.name,
        `--zone=${config.zone}`, `--project=${config.projectId}`, '--quiet',
      ])
      log('Instance deleted')
    }
  }
}
