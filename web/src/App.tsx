import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { Dashboard } from './components/Dashboard'
import { QrPage } from './components/QrPage'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/qr" element={<QrPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
