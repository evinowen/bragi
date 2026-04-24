export interface Indexer {
  name: string
  url: string
  api_key?: string
  api_path?: string
  television?: boolean
  movies?: boolean
  categories?: number[]
  anime_categories?: number[]
}

export interface Config {
  gcp_project_id?: string
  gcp_zone?: string
  gcp_machine_type?: string
  skip_cleanup?: boolean
  setup_firewall?: boolean
  sabnzbd?: { max_download_speed?: string }
  usenet?: {
    host?: string
    username?: string
    password?: string
    ssl?: boolean
  }
  indexers?: Indexer[]
}
