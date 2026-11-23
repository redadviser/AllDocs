// Local development or tests. Anything else (including NODE_ENV left unset
// on a server) is treated as production, so a missing setting never opens
// a development shortcut.
export function isLocalDevelopment(): boolean {
  return process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test'
}
