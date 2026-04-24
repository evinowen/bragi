import * as fs from 'node:fs'
import * as os from 'node:os'
import path from 'node:path'
import type { Indexer } from './types'

const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bragi-deploy-'))

export const results = {
  pass: 0,
  fail: 0,
}

export const vm = {
  created: false,
  name: `bragi-test-${String(Math.floor(Date.now() / 1000))}`,
  ip: '',
}

export const work = {
  dir: workDir,
  sshKey: path.join(workDir, 'id_rsa'),
}

export const config = {
  projectId: '',
  zone: '',
  machineType: 'e2-standard-2',
  skipCleanup: false,
  doFirewall: false,
  usenetHost: '',
  usenetUser: '',
  usenetPass: '',
  usenetSsl: true,
  indexers: [] as Indexer[],
  sabnzbdMaxSpeed: '',
  services: {} as Record<string, boolean>,
}
