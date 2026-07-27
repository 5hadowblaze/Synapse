import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useState } from 'react'

type ClawdState = 'waving' | 'running' | 'working' | 'waiting' | 'review' | 'idle'

type GuideCopy = { state: ClawdState; message: string }

const ASSET: Record<ClawdState, string> = {
  idle: 'clawd-idle.gif',
  waving: 'clawd-waving.gif',
  waiting: 'clawd-waiting.gif',
  working: 'clawd-running.gif',
  review: 'clawd-review.gif',
  running: 'clawd-running.gif',
}

const GUIDE: Record<string, GuideCopy> = {
  hero: { state: 'waving', message: 'Let’s learn your baseline.' },
  story: { state: 'working', message: 'The timer only knows the time. Synapse watches the block.' },
  loop: { state: 'running', message: 'Measure, work, pause, measure again.' },
  surfaces: { state: 'waiting', message: 'Phone, Watch, voice, and the microscope.' },
  clawd: { state: 'review', message: 'I add the context sensors can’t hear.' },
  microscope: { state: 'working', message: 'This is the microscope.' },
  evidence: { state: 'waiting', message: 'Your own baseline is the reference.' },
  built: { state: 'waving', message: 'TestFlight soon. I’m packing.' },
}

export function ClawdGuide({ section }: { section: string }) {
  const [open, setOpen] = useState(true)
  const guide = GUIDE[section] ?? GUIDE.hero

  useEffect(() => {
    setOpen(true)
    const timer = window.setTimeout(() => setOpen(false), 4600)
    return () => window.clearTimeout(timer)
  }, [section])

  return (
    <motion.aside
      className={`clawd-guide is-${section}`}
      aria-label="Clawd, Synapse's voice companion"
      layout
      initial={false}
      animate={{ x: 0, y: 0 }}
      transition={{ type: 'spring', stiffness: 90, damping: 15, mass: 0.8 }}
    >
      <AnimatePresence>
        {open && (
          <motion.p
            className="clawd-bubble"
            initial={{ opacity: 0, y: 10, scale: 0.94 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.94 }}
          >
            {guide.message}
          </motion.p>
        )}
      </AnimatePresence>
      <button
        className="clawd-button"
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-expanded={open}
        aria-label={open ? 'Hide Clawd message' : 'Ask Clawd about this section'}
      >
        <img
          className={`clawd-sprite state-${guide.state}`}
          src={`${import.meta.env.BASE_URL}media/${ASSET[guide.state]}`}
          alt=""
          aria-hidden="true"
        />
      </button>
    </motion.aside>
  )
}
