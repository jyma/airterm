import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { PairPage } from '@/pages/PairPage'
import { SessionsPage } from '@/pages/SessionsPage'
import { SettingsPage } from '@/pages/SettingsPage'
import { getStoredPairing } from '@/lib/storage'

function RequirePairing({ children }: { readonly children: React.ReactNode }) {
  const pairing = getStoredPairing()
  if (!pairing) {
    return <Navigate to="/pair" replace />
  }
  return <>{children}</>
}

export function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/pair" element={<PairPage />} />
        <Route
          path="/sessions"
          element={
            <RequirePairing>
              <SessionsPage />
            </RequirePairing>
          }
        />
        <Route
          path="/settings"
          element={
            <RequirePairing>
              <SettingsPage />
            </RequirePairing>
          }
        />
        <Route path="*" element={<Navigate to="/sessions" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
