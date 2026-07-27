import { motion } from 'motion/react'

export function MakerGuide({ section }: { section: string }) {
  const isBuilt = section === 'built'

  return (
    <motion.aside
      className={`maker-guide${isBuilt ? ' is-built' : ''}`}
      aria-label="Built by Dzak Dzulzalani"
      layout
      transition={{ type: 'spring', stiffness: 100, damping: 20, mass: 0.9 }}
    >
      <img src={`${import.meta.env.BASE_URL}media/dzak-dzulzalani.jpg`} alt="Dzak Dzulzalani" />
      <span className="maker-guide-name">Built by <b>Dzak Dzulzalani</b></span>
    </motion.aside>
  )
}
