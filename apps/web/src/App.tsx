import { Navigate, Route, Routes } from 'react-router-dom'
import { PairPage } from './pages/PairPage'
import { PairedPage } from './pages/PairedPage'
import { getStoredPairing } from './lib/storage'

/// Top-level router. Two routes:
///   /pair  — initial setup; QR scan or manual pair-code entry
///   /     — landing; redirects to /paired if a token exists, /pair otherwise
///   /paired — minimal "you're connected" placeholder until the takeover
///             surface lands in a later phase
export function App() {
  return (
    <Routes>
      <Route path="/" element={<RootRedirect />} />
      <Route path="/pair" element={<PairPage />} />
      <Route path="/paired" element={<PairedPage />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

function RootRedirect() {
  const stored = getStoredPairing()
  return <Navigate to={stored ? '/paired' : '/pair'} replace />
}
