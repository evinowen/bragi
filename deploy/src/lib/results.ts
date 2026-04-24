import { GREEN, NC, RED } from './constants'
import { results, vm } from './state'

export function reportResults(): void {
  console.log()
  console.log('========================================')
  console.log('          Test Results Summary')
  console.log('========================================')
  console.log(`  ${GREEN}Passed: ${results.pass}${NC}`)
  console.log(`  ${RED}Failed: ${results.fail}${NC}`)
  console.log('========================================')

  if (results.fail === 0) {
    console.log(`\n${GREEN}All tests passed — bragi installed successfully.${NC}\n`)
    console.log('=== Service Web Interfaces ===')
    console.log(`  SABnzbd:  http://${vm.ip}/sabnzbd`)
    console.log(`  Sonarr:   http://${vm.ip}/sonarr`)
    console.log(`  Radarr:   http://${vm.ip}/radarr`)
    console.log()
    process.exit(0)
  }
  else {
    console.log(`\n${RED}${results.fail} test(s) failed. Review output above for details.${NC}\n`)
    process.exit(1)
  }
}
