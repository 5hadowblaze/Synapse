import { motion, type HTMLMotionProps } from 'motion/react'
import type { ReactNode } from 'react'
import { easeOut, staggerContainer, staggerItem } from '../../motion/tokens'

interface RevealProps {
  children: ReactNode
  className?: string
  /** Remount / replay stagger when this changes (session, module, mode). */
  replayKey: string
}

/** Staggers children in on mount / when replayKey changes. */
export function Reveal({ children, className, replayKey }: RevealProps) {
  return (
    <motion.div
      key={replayKey}
      className={className}
      variants={staggerContainer}
      initial="initial"
      animate="animate"
    >
      {children}
    </motion.div>
  )
}

export function RevealItem({
  children,
  className,
  ...rest
}: HTMLMotionProps<'div'>) {
  return (
    <motion.div className={className} variants={staggerItem} {...rest}>
      {children}
    </motion.div>
  )
}

interface ChartRevealProps {
  children: ReactNode
  className?: string
  replayKey: string
}

/** Soft rise + fade for chart panels; SVG draw is handled inside via CSS. */
export function ChartReveal({ children, className, replayKey }: ChartRevealProps) {
  return (
    <motion.div
      key={replayKey}
      className={className}
      initial={{ opacity: 0, y: 18, scale: 0.985 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ duration: 0.45, ease: easeOut }}
    >
      {children}
    </motion.div>
  )
}
