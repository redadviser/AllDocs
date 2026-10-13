// Waking devices that wait for news (long polling): each open app keeps one
// GET /api/sync/wait hanging, answered as soon as another of the account's
// devices sends changes, asks for a file, uploads one or joins — so the
// change shows up on the others within a second or two, without push
// notifications. In memory: one server process (behind several, this would
// need a shared channel like Postgres LISTEN/NOTIFY).

type Waiter = { deviceId: string; wake: () => void }

const waiters = new Map<string, Set<Waiter>>()

/// Wakes the account's waiting devices, except [exceptDeviceId] (the one
/// that caused it).
export function notifyDevices(userId: string, exceptDeviceId?: string) {
  const set = waiters.get(userId)
  if (!set) return
  for (const waiter of [...set]) {
    if (waiter.deviceId !== exceptDeviceId) waiter.wake()
  }
}

/// Resolves true when woken, false after [timeoutMs] or when [cancelled].
export function waitForNews(
  userId: string,
  deviceId: string,
  timeoutMs: number,
  onCancel: (cancel: () => void) => void
): Promise<boolean> {
  return new Promise((resolve) => {
    let set = waiters.get(userId)
    if (!set) {
      set = new Set()
      waiters.set(userId, set)
    }
    const done = (woken: boolean) => {
      clearTimeout(timer)
      set!.delete(waiter)
      if (set!.size === 0) waiters.delete(userId)
      resolve(woken)
    }
    const waiter: Waiter = { deviceId, wake: () => done(true) }
    const timer = setTimeout(() => done(false), timeoutMs)
    set.add(waiter)
    onCancel(() => done(false))
  })
}
