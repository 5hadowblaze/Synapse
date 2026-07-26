import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useRef } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useSession } from '../hooks/useSession'
import { DEFAULT_SESSION_ID } from '../lib/firebase'
import { duration, easeOut, viewSlide } from '../motion/tokens'
import {
  isFocusModule,
  type ParsedModule,
  type Session,
  type SessionModule,
} from '../types/session'
import { BreakPointBanner } from './BreakPointBanner'
import { ClockSyncBadge } from './ClockSyncBadge'
import { LabView } from './LabView'
import { SessionPicker } from './SessionPicker'
import { SynapseMark } from './SynapseMark'
import { FocusFadeBanner } from './focus/FocusFadeBanner'
import { FocusView } from './focus/FocusView'

/** /demo/:module → canned snapshot, for a net-less pitch. */
const DEMO_ROUTE_MODULES: Record<string, SessionModule> = {
  focus: 'focusDesk',
  vision: 'visionPvt',
  kinetic: 'kineticClock',
}

const DEMO_PATH: Record<SessionModule, string> = {
  focusDesk: '/demo/focus',
  visionPvt: '/demo/vision',
  kineticClock: '/demo/kinetic',
}

const MODULE_ORDER: Record<string, number> = {
  focusDesk: 0,
  visionPvt: 1,
  kineticClock: 2,
  unknown: 3,
}

interface Copy {
  eyebrow: string
  headline: string
  blurb: string
}

function copyFor(module: ParsedModule): Copy {
  switch (module) {
    case 'focusDesk':
      return {
        eyebrow: 'Focus Desk',
        headline: 'Deep-work fade monitor',
        blurb:
          'Health-aware Pomodoro. Watch heart rate, face arousal, and wrist stillness fuse into one fade score — the block ends when the brain is done, not when the clock says.',
      }
    case 'kineticClock':
      return {
        eyebrow: 'Kinetic Clock',
        headline: 'Spatial-Motor Monitor',
        blurb:
          'Eight-direction clock. Timing is always kept; spatialMatch flags whether the punch went the right way.',
      }
    case 'visionPvt':
      return {
        eyebrow: 'Vision PVT',
        headline: 'Oculomotor PVT Monitor',
        blurb: 'Single-flash oculomotor PVT — saccade onset and arousal, no punch board.',
      }
    default:
      return {
        eyebrow: 'Unknown module',
        headline: 'Unrecognized session',
        blurb: 'This session reports a module the dashboard has no view for.',
      }
  }
}

function UnknownModuleCard({ session }: { session: Session }) {
  return (
    <section className="rounded-sm border border-alert/40 bg-panel/70 px-5 py-6">
      <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-alert">
        Unsupported module
      </div>
      <h2 className="mt-2 font-display text-xl font-semibold text-fog">
        Session “{session.id}” reports module “{session.moduleRaw ?? 'missing'}”
      </h2>
      <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted">
        Nothing is rendered rather than guessing — a Focus block shown through the Vision PVT view
        would be wrong data, not partial data. Known modules are{' '}
        <span className="font-mono text-signal">focusDesk</span>,{' '}
        <span className="font-mono text-visual">visionPvt</span>, and{' '}
        <span className="font-mono text-motor">kineticClock</span>. Update{' '}
        <span className="font-mono text-fog">web/src/types/session.ts</span> and{' '}
        <span className="font-mono text-fog">docs/SCHEMA.md</span> together when the phone starts
        writing a new one.
      </p>
    </section>
  )
}

export function Dashboard() {
  const params = useParams<{ sessionId?: string; module?: string }>()
  const navigate = useNavigate()
  const routeDemoModule = params.module ? (DEMO_ROUTE_MODULES[params.module] ?? null) : null

  const {
    mode,
    sessionId,
    setSessionId,
    snapshot,
    error,
    forceDemo,
    exitDemo,
    isDemoForced,
  } = useSession(params.sessionId ?? DEFAULT_SESSION_ID, routeDemoModule)

  useEffect(() => {
    if (params.sessionId) setSessionId(params.sessionId)
  }, [params.sessionId, setSessionId])

  useEffect(() => {
    if (routeDemoModule) forceDemo(routeDemoModule)
  }, [routeDemoModule, forceDemo])

  const session = snapshot?.session
  const trials = snapshot?.trials ?? []
  const epochs = snapshot?.epochs ?? []
  const focus = session ? isFocusModule(session.module) : false

  const latestEpoch = epochs.length > 0 ? epochs[epochs.length - 1] : null
  const liveFadeEpoch =
    focus && session?.status === 'active' && latestEpoch?.fadeSuggested ? latestEpoch : null
  const hrAnchor = epochs.find((e) => e.hrBpm != null)?.hrBpm ?? null

  const breakPointTrial = focus ? null : (session?.breakPointTrial ?? null)

  const copy = copyFor(session?.module ?? 'focusDesk')
  const glow = focus
    ? 'radial-gradient(ellipse 80% 50% at 50% -10%, rgba(255,122,138,0.07), transparent), linear-gradient(180deg, #0a1018 0%, #070b10 40%, #05080c 100%)'
    : 'radial-gradient(ellipse 80% 50% at 50% -10%, rgba(61,255,196,0.08), transparent), linear-gradient(180deg, #0a1018 0%, #070b10 40%, #05080c 100%)'

  const viewKey = `${mode}-${session?.module ?? 'none'}-${session?.id ?? sessionId}`

  // Direction for horizontal slide (±1). Updated during render when module changes.
  const prevModuleRef = useRef<ParsedModule | null>(null)
  const slideDirRef = useRef(1)
  const currentModule = session?.module ?? null
  if (
    currentModule &&
    prevModuleRef.current &&
    prevModuleRef.current !== currentModule
  ) {
    const from = MODULE_ORDER[prevModuleRef.current] ?? 0
    const to = MODULE_ORDER[currentModule] ?? 0
    slideDirRef.current = to >= from ? 1 : -1
  }
  if (currentModule) prevModuleRef.current = currentModule

  function handleForceDemo(module: SessionModule = 'focusDesk') {
    forceDemo(module)
    navigate(DEMO_PATH[module])
  }

  function handleExitDemo() {
    exitDemo()
    navigate('/')
  }

  return (
    <div className="relative min-h-full bg-ink">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.35] transition-[background] duration-500"
        style={{ backgroundImage: glow }}
      />

      <div className="relative mx-auto flex max-w-[1600px] flex-col gap-4 px-5 pb-8 pt-6">
        <BreakPointBanner breakPointTrial={breakPointTrial} />
        <FocusFadeBanner epoch={liveFadeEpoch} hrAnchor={hrAnchor} />

        <header className="flex flex-wrap items-end justify-between gap-4 border-b border-line pb-4">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2.5">
              <SynapseMark className="h-7 w-7 shrink-0 rounded-[7px] ring-1 ring-line" />
              <div className="font-mono text-[10px] uppercase tracking-[0.35em] text-signal">
                Synapse · {focus ? 'Focus HUD' : 'Clinical HUD'} · {copy.eyebrow}
              </div>
            </div>
            <AnimatePresence mode="wait">
              <motion.div
                key={copy.headline}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={{ duration: 0.28, ease: easeOut }}
              >
                <h1 className="mt-1 font-display text-3xl font-semibold tracking-tight text-fog md:text-4xl">
                  {copy.headline}
                </h1>
                <p className="mt-1 max-w-xl text-sm text-muted">{copy.blurb}</p>
              </motion.div>
            </AnimatePresence>
          </div>
          <div className="flex flex-col items-end gap-2">
            {session ? <ClockSyncBadge session={session} /> : null}
            <Link
              to="/qr"
              className="btn-press font-mono text-[10px] uppercase tracking-wider text-muted hover:text-signal"
            >
              Dashboard QR →
            </Link>
          </div>
        </header>

        <SessionPicker
          sessionId={sessionId}
          onChange={setSessionId}
          mode={mode}
          isDemoForced={isDemoForced}
          onForceDemo={handleForceDemo}
          onExitDemo={handleExitDemo}
          error={error}
          module={session?.module ?? null}
          status={session?.status ?? null}
        />

        <div className="relative overflow-hidden">
          <AnimatePresence mode="wait" custom={slideDirRef.current}>
            <motion.div
              key={viewKey}
              custom={slideDirRef.current}
              variants={viewSlide}
              initial="enter"
              animate="center"
              exit="exit"
              transition={{ duration: duration.enter, ease: easeOut }}
              className="flex flex-col gap-4"
            >
              {!session ? (
                <div className="flex min-h-[260px] items-center justify-center rounded-sm border border-line bg-panel/50 font-mono text-xs text-muted">
                  Waiting for session…
                </div>
              ) : session.module === 'unknown' ? (
                <UnknownModuleCard session={session} />
              ) : focus ? (
                <FocusView session={session} epochs={epochs} mode={mode} />
              ) : (
                <LabView session={session} trials={trials} />
              )}
            </motion.div>
          </AnimatePresence>
        </div>
      </div>
    </div>
  )
}
