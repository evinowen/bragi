import path from 'node:path'

export const DEPLOY_DIR = path.join(__dirname, '..', '..')
export const SCRIPTS_DIR = path.join(DEPLOY_DIR, 'scripts')
export const CONFIG_FILE = path.join(DEPLOY_DIR, 'deploy.json')

export const IMAGE_FAMILY = 'ubuntu-2204-lts'
export const IMAGE_PROJECT = 'ubuntu-os-cloud'
export const DISK_SIZE = '30GB'
export const NETWORK_TAG = 'bragi-test'
export const SSH_USER = 'bragi'

export const RED = '[0;31m'
export const GREEN = '[0;32m'
export const YELLOW = '[1;33m'
export const CYAN = '[0;36m'
export const NC = '[0m'
