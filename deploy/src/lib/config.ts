import * as fs from 'node:fs'
import { CONFIG_FILE } from './constants'
import { config } from './state'
import type { Config } from './types'

export function loadConfig(): void {
  if (!fs.existsSync(CONFIG_FILE)) {
    console.error(`ERROR: ${CONFIG_FILE} not found.`)
    process.exit(1)
  }

  const cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')) as Config

  config.projectId = cfg.gcp_project_id ?? ''
  config.zone = cfg.gcp_zone ?? ''
  config.machineType = cfg.gcp_machine_type ?? 'e2-standard-2'
  config.skipCleanup = cfg.skip_cleanup ?? false
  config.doFirewall = cfg.setup_firewall ?? false

  config.usenetHost = cfg.usenet?.host ?? ''
  config.usenetUser = cfg.usenet?.username ?? ''
  config.usenetPass = cfg.usenet?.password ?? ''
  config.usenetSsl = cfg.usenet?.ssl ?? true

  config.indexers = cfg.indexers ?? []
  config.sabnzbdMaxSpeed = cfg.sabnzbd?.max_download_speed ?? ''

  const allServices = ['nginx', 'sabnzbd', 'sonarr', 'radarr', 'jellyfin']
  const servicesCfg = cfg.services ?? {}
  config.services = Object.fromEntries(
    allServices.map(svc => [svc, servicesCfg[svc] !== false])
  )
}
