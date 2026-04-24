import * as fs from 'node:fs'
import path from 'node:path'
import { SCRIPTS_DIR } from './constants'
import { config, work } from './state'

function readScript(name: string): string {
  return fs.readFileSync(path.join(SCRIPTS_DIR, name), 'utf8')
}

function writeScript(filePath: string, content: string): void {
  fs.writeFileSync(filePath, content, { encoding: 'utf8' })
}

export function writeScripts(): void {
  writeScript(path.join(work.dir, 'setup.sh'), readScript('setup.sh'))

  const allServices = ['nginx', 'sabnzbd', 'sonarr', 'radarr', 'jellyfin', 'plex']
  const enabledServices = allServices.filter(svc => config.services[svc])
  const disabledServices = allServices.filter(svc => !config.services[svc])
  const enabledServicesStr = enabledServices.join(' ')
  const disabledServicesStr = disabledServices.join(' ')

  const indexersB64 = Buffer.from(JSON.stringify(config.indexers)).toString('base64')
  const sslResponse = config.usenetSsl ? '' : 'n'
  const runInstall = readScript('run_install.sh')
    .replace('__INDEXERS_B64__', () => indexersB64)
    .replace('__USENET_HOST__', () => config.usenetHost)
    .replace('__USENET_USER__', () => config.usenetUser)
    .replace('__USENET_PASS__', () => config.usenetPass)
    .replace('__SSL_RESPONSE__', () => sslResponse)
    .replace('__SABNZBD_MAX_SPEED__', () => config.sabnzbdMaxSpeed)
    .replace('__DISABLED_SERVICES__', () => disabledServicesStr)
  writeScript(path.join(work.dir, 'run_install.sh'), runInstall)

  const verify = readScript('verify.sh')
    .replace('__ENABLED_SERVICES__', () => enabledServicesStr)
  writeScript(path.join(work.dir, 'verify.sh'), verify)
}
