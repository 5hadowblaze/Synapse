import { AnimatePresence, motion } from 'motion/react'
import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { Dashboard } from './components/Dashboard'
import { QrPage } from './components/QrPage'
import { pageTransition } from './motion/tokens'

function AnimatedRoutes() {
  const location = useLocation()
  // Keep Dashboard mounted across / · /demo/* · /session/* so module swaps
  // use the in-dashboard slide instead of a full remount.
  const shell = location.pathname.startsWith('/qr') ? 'qr' : 'dashboard'

  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={shell}
        className="min-h-full"
        initial={pageTransition.initial}
        animate={pageTransition.animate}
        exit={pageTransition.exit}
      >
        <Routes location={location}>
          <Route path="/" element={<Dashboard />} />
          <Route path="/session/:sessionId" element={<Dashboard />} />
          <Route path="/demo/:module" element={<Dashboard />} />
          <Route path="/qr" element={<QrPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </motion.div>
    </AnimatePresence>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AnimatedRoutes />
    </BrowserRouter>
  )
}
