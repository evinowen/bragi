#!/usr/bin/env tsx

import { cleanup } from './lib/cleanup'
import { loadConfig } from './lib/config'
import { setupFirewall } from './lib/firewall'
import { createInstance } from './lib/instance'
import { installDependencies, runInstaller, verifyInstallation } from './lib/phases'
import { checkPrerequisites } from './lib/prerequisites'
import { reportResults } from './lib/results'
import { writeScripts } from './lib/scripts'

process.on('exit', cleanup)

async function main(): Promise<void> {
  loadConfig()
  checkPrerequisites()
  setupFirewall()
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
