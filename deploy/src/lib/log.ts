import { CYAN, GREEN, NC, RED, YELLOW } from './constants'
import { results } from './state'

export function log(msg: string): void {
  console.log(`${CYAN}[DEPLOY]${NC}  ${msg}`)
}

export function logWarn(msg: string): void {
  console.log(`${YELLOW}[WARN]${NC}  ${msg}`)
}

export function logSuccess(msg: string): void {
  results.pass++
  console.log(`${GREEN}[PASS]${NC}  ${msg}`)
}

export function logFailure(msg: string): void {
  results.fail++
  console.log(`${RED}[FAIL]${NC}  ${msg}`)
}
