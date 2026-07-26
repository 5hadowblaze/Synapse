/** Shared motion tokens — strong ease-out, keep UI under ~400ms except chart draw. */
export const easeOut = [0.23, 1, 0.32, 1] as const
export const easeInOut = [0.77, 0, 0.175, 1] as const

export const duration = {
  press: 0.12,
  hover: 0.18,
  enter: 0.36,
  exit: 0.28,
  chart: 0.85,
  count: 0.7,
  banner: 0.38,
} as const

/** Route-level (/, /qr) — soft vertical. */
export const pageTransition = {
  initial: { opacity: 0, y: 16 },
  animate: {
    opacity: 1,
    y: 0,
    transition: { duration: duration.enter, ease: easeOut },
  },
  exit: {
    opacity: 0,
    y: -12,
    transition: { duration: duration.exit, ease: easeOut },
  },
}

/** Demo / module swaps — directional horizontal slide. `custom` = ±1. */
export const viewSlide = {
  enter: (dir: number) => ({
    opacity: 0,
    x: dir * 56,
  }),
  center: {
    opacity: 1,
    x: 0,
  },
  exit: (dir: number) => ({
    opacity: 0,
    x: dir * -40,
  }),
}

export const staggerContainer = {
  initial: {},
  animate: {
    transition: { staggerChildren: 0.055, delayChildren: 0.06 },
  },
}

export const staggerItem = {
  initial: { opacity: 0, y: 14, scale: 0.98 },
  animate: {
    opacity: 1,
    y: 0,
    scale: 1,
    transition: { duration: duration.enter, ease: easeOut },
  },
}
