import { publicBaseUrl } from '../modules/password/password.service'

// The address people see in the links the app hands out (document requests
// /r/..., secure shares /s/...). A short domain pointed at this same server
// (e.g. https://requests.eupasoft.com) reads better than the API host.
export function linksBaseUrl(requestOrigin: string): string {
  const configured = process.env.REQUESTS_PUBLIC_URL?.trim().replace(/\/+$/, '')
  return configured || publicBaseUrl(requestOrigin)
}

/// A link token: 128 random bits, 22 URL-safe characters.
export const LINK_TOKEN_PATTERN = /^[A-Za-z0-9_-]{20,64}$/
