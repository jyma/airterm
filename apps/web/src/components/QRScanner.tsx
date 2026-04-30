import { useEffect, useRef, useState } from 'react'

/// Live-camera QR scanner. Uses the built-in `BarcodeDetector` API
/// (Chromium / WebKit on iOS 17+) to avoid pulling in a JS decoder library.
/// Caller chooses the fallback path when the API is missing — typically a
/// manual pair-code entry form.
///
/// Surface intentionally narrow: starts the camera on mount, stops it on
/// unmount, fires `onResult` with the raw decoded text on first hit.
/// Repeated scans of the same code are debounced; the parent should
/// react by unmounting the scanner.
interface QRScannerProps {
  readonly onResult: (text: string) => void
  readonly onError: (error: QRScannerError) => void
}

export type QRScannerErrorCode =
  | 'unsupported'
  | 'permission_denied'
  | 'no_camera'
  | 'unknown'

export interface QRScannerError {
  readonly code: QRScannerErrorCode
  readonly message: string
}

interface BarcodeDetectorLike {
  detect(source: CanvasImageSource): Promise<{ rawValue: string }[]>
}

interface BarcodeDetectorCtor {
  new (init?: { formats?: string[] }): BarcodeDetectorLike
  getSupportedFormats?(): Promise<string[]>
}

const BarcodeDetectorClass = (
  globalThis as { BarcodeDetector?: BarcodeDetectorCtor }
).BarcodeDetector

const SCAN_INTERVAL_MS = 250

export function QRScanner({ onResult, onError }: QRScannerProps) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const stoppedRef = useRef(false)
  const lastResultRef = useRef<string | null>(null)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    stoppedRef.current = false
    if (!BarcodeDetectorClass) {
      onError({
        code: 'unsupported',
        message:
          'This browser does not support the BarcodeDetector API. Use the manual pair code option below.',
      })
      return
    }

    const detector = new BarcodeDetectorClass({ formats: ['qr_code'] })

    async function startCamera(): Promise<void> {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'environment' },
          audio: false,
        })
        if (stoppedRef.current) {
          stream.getTracks().forEach((t) => t.stop())
          return
        }
        streamRef.current = stream
        const video = videoRef.current
        if (!video) return
        video.srcObject = stream
        await video.play()
        setReady(true)
        scheduleScan(detector)
      } catch (e) {
        const err = e as DOMException
        if (err.name === 'NotAllowedError' || err.name === 'SecurityError') {
          onError({ code: 'permission_denied', message: 'Camera permission denied.' })
        } else if (err.name === 'NotFoundError') {
          onError({ code: 'no_camera', message: 'No camera found on this device.' })
        } else {
          onError({ code: 'unknown', message: err.message ?? 'Camera failed to start.' })
        }
      }
    }

    function scheduleScan(d: BarcodeDetectorLike): void {
      if (stoppedRef.current) return
      const video = videoRef.current
      if (!video || video.readyState < 2) {
        setTimeout(() => scheduleScan(d), SCAN_INTERVAL_MS)
        return
      }
      d.detect(video)
        .then((codes) => {
          if (stoppedRef.current) return
          const hit = codes[0]?.rawValue
          if (hit && hit !== lastResultRef.current) {
            lastResultRef.current = hit
            onResult(hit)
            return
          }
          setTimeout(() => scheduleScan(d), SCAN_INTERVAL_MS)
        })
        .catch(() => {
          if (stoppedRef.current) return
          setTimeout(() => scheduleScan(d), SCAN_INTERVAL_MS)
        })
    }

    void startCamera()

    return () => {
      stoppedRef.current = true
      streamRef.current?.getTracks().forEach((t) => t.stop())
      streamRef.current = null
    }
    // intentionally omit handlers — they're stable for a given scanner mount
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div
      style={{
        position: 'relative',
        width: '100%',
        aspectRatio: '1 / 1',
        background: 'var(--color-bg-tertiary)',
        borderRadius: 'var(--radius-card)',
        overflow: 'hidden',
      }}
    >
      <video
        ref={videoRef}
        playsInline
        muted
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          display: ready ? 'block' : 'none',
        }}
      />
      {!ready && (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            display: 'grid',
            placeItems: 'center',
            color: 'var(--color-text-secondary)',
            fontSize: 14,
          }}
        >
          Starting camera…
        </div>
      )}
      <ScanOverlay />
    </div>
  )
}

/// Decorative crosshair / corner brackets so the camera preview looks
/// like a scanner instead of a webcam feed. Pure CSS — no React state.
function ScanOverlay() {
  const corner: React.CSSProperties = {
    position: 'absolute',
    width: 24,
    height: 24,
    borderColor: 'var(--color-accent-blue)',
    borderStyle: 'solid',
    borderWidth: 0,
  }
  return (
    <>
      <span style={{ ...corner, top: 16, left: 16, borderTopWidth: 3, borderLeftWidth: 3 }} />
      <span style={{ ...corner, top: 16, right: 16, borderTopWidth: 3, borderRightWidth: 3 }} />
      <span style={{ ...corner, bottom: 16, left: 16, borderBottomWidth: 3, borderLeftWidth: 3 }} />
      <span style={{ ...corner, bottom: 16, right: 16, borderBottomWidth: 3, borderRightWidth: 3 }} />
    </>
  )
}
