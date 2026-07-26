import { AnimatePresence, motion } from 'motion/react'
import type { ReactNode } from 'react'
import { duration, easeOut } from '../../motion/tokens'

interface AlertBannerShellProps {
  show: boolean
  /** Unique key so successive banners remount cleanly. */
  bannerKey: string
  tone: 'amber' | 'alert'
  children: ReactNode
  role?: 'status' | 'alert'
}

const toneClass = {
  amber:
    'border-amber bg-amber text-ink shadow-[0_12px_40px_rgba(240,180,41,0.35)]',
  alert:
    'border-alert bg-alert text-ink shadow-[0_12px_40px_rgba(255,59,78,0.45)]',
} as const

/**
 * In-flow banner: height expands so the page eases down with it
 * (no fixed overlay + padding jump).
 */
export function AlertBannerShell({
  show,
  bannerKey,
  tone,
  children,
  role = 'status',
}: AlertBannerShellProps) {
  return (
    <AnimatePresence initial={false}>
      {show ? (
        <motion.div
          key={bannerKey}
          className="relative z-40 overflow-hidden"
          initial={{ height: 0, opacity: 0 }}
          animate={{ height: 'auto', opacity: 1 }}
          exit={{ height: 0, opacity: 0 }}
          transition={{ duration: duration.banner, ease: easeOut }}
        >
          <motion.div
            className={`border-b-2 ${toneClass[tone]}`}
            role={role}
            initial={{ y: -12 }}
            animate={{ y: 0 }}
            exit={{ y: -8 }}
            transition={{ duration: duration.banner, ease: easeOut }}
          >
            {children}
          </motion.div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  )
}
