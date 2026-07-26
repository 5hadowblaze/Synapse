import { doc, getDoc } from 'firebase/firestore'
import { getDb } from '../lib/firebase'

/** Reads `live/focus` pointer written by the phone when a Focus block starts. */
export async function fetchLiveFocusSessionId(): Promise<{
  sessionId: string | null
  error: string | null
}> {
  const db = getDb()
  if (!db) return { sessionId: null, error: 'Firestore unavailable' }
  try {
    const snap = await getDoc(doc(db, 'live', 'focus'))
    if (!snap.exists()) {
      return { sessionId: null, error: 'No live/focus pointer yet — start a Focus block on the phone.' }
    }
    const data = snap.data() as Record<string, unknown>
    const id = typeof data.sessionId === 'string' ? data.sessionId : null
    const status = typeof data.status === 'string' ? data.status : null
    if (!id || status === 'idle') {
      return {
        sessionId: null,
        error: 'No active Focus block — start one on the phone with Watch HR running.',
      }
    }
    return { sessionId: id, error: null }
  } catch (err) {
    return {
      sessionId: null,
      error: err instanceof Error ? err.message : 'Failed to read live/focus',
    }
  }
}
