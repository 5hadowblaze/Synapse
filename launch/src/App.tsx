import { AnimatePresence, motion, useInView, useScroll, useSpring, useTransform } from 'motion/react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { ClawdGuide } from './components/ClawdGuide'
import { MakerGuide } from './components/MakerGuide'

const base = import.meta.env.BASE_URL
const media = (name: string) => `${base}media/${name}`

const links = {
  dashboard: 'https://synapse-clinical-hz.web.app/demo/focus',
  github: 'https://github.com/5hadowblaze/Synapse',
}

const sections = [
  ['story', 'Story'],
  ['loop', 'The loop'],
  ['surfaces', 'Surfaces'],
  ['clawd', 'Clawd'],
  ['microscope', 'Microscope'],
  ['evidence', 'Evidence'],
]

function useActiveSection() {
  const [active, setActive] = useState('hero')
  useEffect(() => {
    const nodes = [...document.querySelectorAll<HTMLElement>('[data-section]')]
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter((entry) => entry.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0]
        if (visible) setActive((visible.target as HTMLElement).dataset.section ?? 'hero')
      },
      { rootMargin: '-36% 0px -45% 0px', threshold: [0.05, 0.35, 0.65] },
    )
    nodes.forEach((node) => observer.observe(node))
    return () => observer.disconnect()
  }, [])
  return active
}

function Reveal({ children, className = '' }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const inView = useInView(ref, { once: true, amount: 0.2 })
  return (
    <motion.div
      ref={ref}
      className={className}
      initial={{ opacity: 0, y: 28, filter: 'blur(10px)' }}
      animate={inView ? { opacity: 1, y: 0, filter: 'blur(0px)' } : {}}
      transition={{ type: 'spring', damping: 23, stiffness: 92, mass: 0.75 }}
    >
      {children}
    </motion.div>
  )
}

function Phone({ image, className = '', label }: { image: string; className?: string; label: string }) {
  return (
    <div className={`phone ${className}`} aria-label={label}>
      <div className="phone-speaker" />
      <img src={media(image)} alt={label} />
      <i className="phone-glint" />
    </div>
  )
}

function Watch() {
  return (
    <div className="watch" aria-label="Apple Watch pacing companion preview">
      <div className="watch-band top" />
      <div className="watch-case">
        <div className="watch-ring"><span>72</span><small>steady</small></div>
        <p>YOUR BASELINE</p>
      </div>
      <div className="watch-band bottom" />
    </div>
  )
}

function Hero() {
  const ref = useRef<HTMLElement>(null)
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start start', 'end start'] })
  const y = useTransform(scrollYProgress, [0, 1], [0, 120])
  const opacity = useTransform(scrollYProgress, [0, 0.85], [1, 0])
  return (
    <section ref={ref} className="hero" data-section="hero">
      <div className="hero-grid" />
      <motion.div className="hero-copy" style={{ opacity, y }}>
        <motion.div className="event-lockup" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.15 }}>
          <div className="eyebrow hero-eyebrow"><span className="dot" /> JUNO HACKATHON BUILD · 2026</div>
          <p className="event-date">SATURDAY 25 JULY → SUNDAY 26 JULY</p>
        </motion.div>
        <motion.img className="brand-mark" src={media('brand-mark.png')} alt="Synapse" initial={{ opacity: 0, scale: 0.7 }} animate={{ opacity: 1, scale: 1 }} transition={{ type: 'spring', delay: 0.2 }} />
        <motion.h1 initial={{ opacity: 0, y: 32 }} animate={{ opacity: 1, y: 0 }} transition={{ type: 'spring', delay: 0.32, damping: 22 }}>
          Healthcare for people<br />who need to <em>lock in.</em>
        </motion.h1>
        <motion.p className="lede" initial={{ opacity: 0, y: 24 }} animate={{ opacity: 1, y: 0 }} transition={{ type: 'spring', delay: 0.48 }}>
          Your health drives the work. Synapse helps you pace both.
        </motion.p>
        <motion.div className="hero-actions" initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ type: 'spring', delay: 0.62 }}>
          <button className="button button-status" type="button" disabled title="Coming to TestFlight soon">Coming to TestFlight soon <span>↗</span></button>
          <a className="text-link" href="#loop">See how it works <span>↓</span></a>
        </motion.div>
      </motion.div>
      <motion.div className="hero-stage" style={{ y }} aria-label="Synapse running on iPhone and Apple Watch">
        <div className="baseline-orbit orbit-one" />
        <div className="baseline-orbit orbit-two" />
        <Phone image="home.png" label="Synapse iOS home with Clawd" className="hero-phone hero-phone-back" />
        <Phone image="focus.png" label="Synapse focus setup with Clawd" className="hero-phone hero-phone-front" />
        <Watch />
        <div className="stage-label label-ios">REAL iOS BUILD</div>
        <div className="stage-label label-watch">WATCH · PACING</div>
      </motion.div>
      <a href="#story" className="scroll-cue" aria-label="Scroll to the Synapse story"><i /> <span>SCROLL TO ENTER</span></a>
    </section>
  )
}

function Story() {
  return (
    <section id="story" className="section story-section" data-section="story">
      <div className="section-index">01</div>
      <Reveal className="section-intro">
        <p className="eyebrow">THE ORIGIN</p>
        <h2>Health is upstream<br />of productivity.</h2>
      </Reveal>
      <div className="story-layout">
        <Reveal className="story-copy">
          <blockquote>“We looked around a room of people locking in—and almost nobody was looking after the system that makes focus possible.”</blockquote>
          <p>The timer is the door. The body is the product.</p>
        </Reveal>
        <Reveal className="origin-image-wrap">
          <img src={media('hackers-origin.png')} alt="A room of hackers working late together" />
          <div className="origin-wash" />
          <span className="annotation a-one"><b>01</b> Timers ignore the body</span>
          <span className="annotation a-two"><b>02</b> Gut feel arrives late</span>
          <span className="annotation a-three"><b>03</b> Context disappears</span>
        </Reveal>
      </div>
    </section>
  )
}

const loopSteps = [
  ['PVT-B', 'A quick reaction check starts the block.', 'pvt.png'],
  ['Baseline', 'A dashed ring learns what today looks like.', 'baseline.png'],
  ['Focus', 'Phone + Watch pace the block in-session.', 'focus.png'],
  ['Break', 'Warmth rises before the block takes more.', 'home.png'],
  ['Recap', 'A second check keeps the session honest.', 'pvt.png'],
  ['Clawd', 'Voice gives the numbers life context.', 'focus.png'],
]

function FocusLoop() {
  const [index, setIndex] = useState(0)
  const ref = useRef<HTMLElement>(null)
  const inView = useInView(ref, { amount: 0.35 })
  useEffect(() => {
    if (!inView) return
    const timer = window.setInterval(() => setIndex((value) => (value + 1) % loopSteps.length), 2600)
    return () => window.clearInterval(timer)
  }, [inView])
  const step = loopSteps[index]
  return (
    <section ref={ref} id="loop" className="section loop-section" data-section="loop">
      <div className="section-index">02</div>
      <Reveal className="loop-heading">
        <p className="eyebrow">THE LOOP</p>
        <h2>Pace before the block<br />takes more than it gives.</h2>
        <p className="muted">A familiar focus ritual, made health-aware against your own baseline.</p>
      </Reveal>
      <div className={`loop-stage step-${index}`}>
        <div className="loop-visual">
          <div className="baseline-ring"><span>LEARNING<br />YOUR<br />BASELINE</span></div>
          <AnimatePresence mode="wait">
            <motion.div key={step[0]} className="loop-screen" initial={{ opacity: 0, scale: 0.9, rotateY: -8 }} animate={{ opacity: 1, scale: 1, rotateY: 0 }} exit={{ opacity: 0, scale: 1.05, rotateY: 8 }} transition={{ duration: 0.45 }}>
              <Phone image={step[2]} label={`Synapse ${step[0]} screen`} />
            </motion.div>
          </AnimatePresence>
          <div className="rt-card"><span>WITHIN-PERSON DELTA</span><strong>280 <i>→</i> 340 <small>ms</small></strong><b>+60 ms</b></div>
        </div>
        <div className="loop-steps" role="tablist" aria-label="Synapse pacing loop">
          {loopSteps.map(([name, description], stepIndex) => (
            <button key={name} type="button" className={stepIndex === index ? 'active' : ''} onClick={() => setIndex(stepIndex)} role="tab" aria-selected={stepIndex === index}>
              <span>{String(stepIndex + 1).padStart(2, '0')}</span><strong>{name}</strong><p>{description}</p>
            </button>
          ))}
        </div>
      </div>
      <div className="loop-spine" aria-hidden="true"><i /><i /><i /><i /><i /><i /></div>
    </section>
  )
}

function Surfaces() {
  return (
    <section id="surfaces" className="section surfaces-section" data-section="surfaces">
      <div className="section-index">03</div>
      <Reveal className="surfaces-heading"><p className="eyebrow">THREE SURFACES</p><h2>One loop. Three jobs.</h2><p className="muted">The same session, shown at the right level of attention.</p></Reveal>
      <div className="surface-constellation">
        <Reveal className="surface surface-phone"><span className="surface-number">01</span><h3>Phone + Watch</h3><p>Start the block. Learn a baseline. Pace the session. Bookend it with PVT-B.</p><div className="mini-device"><Phone image="baseline.png" label="Baseline screen" /><Watch /></div><b>ACT IN THE MOMENT</b></Reveal>
        <Reveal className="surface surface-voice"><span className="surface-number">02</span><h3>Clawd</h3><p>Carry sleep, stress, caffeine and life context into the recap.</p><div className="voice-orb"><i /><i /><i /><span>VOICE<br />RECAP</span></div><b>HEAR THE CONTEXT</b></Reveal>
        <Reveal className="surface surface-web"><span className="surface-number">03</span><h3>Web dashboard</h3><p>Focus timeline, fade score, heart rate, phase, channels and pacing report.</p><img src={media('dashboard-timeline.png')} alt="Synapse dashboard timeline" /><b>INSPECT THE FINE GRAIN</b></Reveal>
        <div className="constellation-line line-one" /><div className="constellation-line line-two" />
      </div>
    </section>
  )
}

function Voice() {
  return (
    <section id="clawd" className="section voice-section" data-section="clawd">
      <div className="section-index">04</div>
      <Reveal className="voice-head"><p className="eyebrow">THE VOICE COMPANION</p><h2>The session<br />has a voice.</h2></Reveal>
      <div className="voice-layout">
        <Reveal className="clawd-spotlight"><div className="voice-rings"><i /><i /><i /></div><img className="clawd-hero-sprite" src={media('clawd-review.gif')} alt="Clawd in review mode" /></Reveal>
        <Reveal className="recap-conversation"><div className="chat from-clawd"><b>CLAWD</b><p>How did that block feel?</p></div><div className="chat from-user"><b>YOU</b><p>I slept badly, and I had coffee late.</p></div><div className="chat from-clawd"><b>CLAWD</b><p>Your reaction check slowed after the block. Let’s keep that context with the session.</p><span className="chat-delta">280 → 340 ms · 2 lapses</span></div></Reveal>
        <Reveal className="voice-note"><p>Sensors see the body.</p><strong>The recap hears the life around it.</strong><span>Clawd reflects the evidence back with you—it does not diagnose you.</span></Reveal>
      </div>
    </section>
  )
}

function Microscope() {
  const ref = useRef<HTMLElement>(null)
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start end', 'end start'] })
  const scan = useSpring(useTransform(scrollYProgress, [0, 1], ['8%', '88%']), { stiffness: 70, damping: 20 })
  return (
    <section ref={ref} id="microscope" className="section microscope-section" data-section="microscope">
      <div className="section-index">05</div>
      <Reveal className="microscope-head"><p className="eyebrow">THE MICROSCOPE</p><h2>Phone = companion.<br />Dashboard = microscope.</h2><p className="muted">The phone keeps the ritual calm. The web opens the fine grain.</p></Reveal>
      <Reveal className="dashboard-frame"><img src={media('dashboard-full.png')} alt="Synapse Focus dashboard showing signal evidence and pacing report" /><motion.i className="dashboard-scan" style={{ left: scan }} /><span className="scan-label">SESSION EVIDENCE</span></Reveal>
      <div className="microscope-caption"><span>FADE SCORE</span><span>HEART RATE</span><span>PHASE</span><span>CHANNEL SIGNALS</span><span>PACING REPORT</span></div>
      <a className="button button-primary dashboard-link" href={links.dashboard} target="_blank" rel="noreferrer">Open the live dashboard <span>↗</span></a>
    </section>
  )
}

function Evidence() {
  return (
    <section id="evidence" className="section evidence-section" data-section="evidence">
      <div className="section-index">06</div>
      <Reveal className="evidence-head"><p className="eyebrow">EVIDENCE, NOT VIBES</p><h2>The numbers keep<br />the nudge honest.</h2></Reveal>
      <div className="evidence-grid">
        <Reveal className="evidence-rt"><span>WITHIN-PERSON DELTA</span><strong>280 <i>→</i> 340 <small>ms</small></strong><b>+60 ms</b><p>Pre and post reaction checks bookend the block. Synapse frames a within-person shift, not a score against population norms.</p></Reveal>
        <Reveal className="evidence-baseline"><div className="baseline-ring small"><span>YOUR<br />OWN<br />BASELINE</span></div><p>We don’t claim to measure fatigue. Synapse uses a wellness signal and a nudge: <b>take a break.</b></p></Reveal>
        <Reveal className="evidence-notes"><article><b>01</b><h3>PVT-B</h3><p>Brief psychomotor vigilance testing is a published measure of behavioural alertness under sleep restriction.</p><cite>Basner, Mollicone & Dinges · Acta Astronautica, 2011</cite></article><article><b>02</b><h3>Sleep matters</h3><p>Chronic sleep restriction is associated with progressive cognitive performance decline.</p><cite>Van Dongen et al. · Sleep, 2003</cite></article></Reveal>
      </div>
    </section>
  )
}

function Close() {
  return (
    <section id="built-by" className="section close-section" data-section="built">
      <div className="close-rings"><i /><i /><i /></div>
      <Reveal className="close-inner">
        <p className="eyebrow close-maker-label">BUILT BY DZAK DZULZALANI</p>
        <h2>Build hard.<br /><em>Pace honestly.</em></h2>
        <p>Synapse is a hackathon build spanning SwiftUI, Apple Watch, HealthKit, on-device sensing, ElevenLabs voice, Firebase and React.</p>
        <div className="close-actions"><button className="button button-status large" type="button" disabled title="Coming to TestFlight soon">Coming to TestFlight soon <span>↗</span></button><a className="button button-quiet" href={links.dashboard} target="_blank" rel="noreferrer">Live dashboard <span>↗</span></a><a className="button button-quiet" href={links.github} target="_blank" rel="noreferrer">GitHub <span>↗</span></a></div>
      </Reveal>
      <footer><span>© 2026 SYNAPSE</span><span>PHONE + WATCH · VOICE · WEB</span><span>COGNITIVE PACING, PVT-ANCHORED</span></footer>
    </section>
  )
}

export default function App() {
  const active = useActiveSection()
  const { scrollYProgress } = useScroll()
  return (
    <main>
      <motion.div className="page-progress" style={{ scaleX: scrollYProgress }} />
      <div className={`ambient ambient-${active}`} aria-hidden="true" />
      <header className="site-nav"><a href="#top" className="nav-logo"><img src={media('brand-mark.png')} alt="Synapse" /><span>Synapse</span></a><nav>{sections.map(([id, label]) => <a key={id} href={`#${id}`} className={active === id ? 'active' : ''}>{label}</a>)}</nav><a className="nav-dashboard" href={links.dashboard} target="_blank" rel="noreferrer">LIVE DASHBOARD ↗</a></header>
      <div id="top" />
      <Hero />
      <Story />
      <FocusLoop />
      <Surfaces />
      <Voice />
      <Microscope />
      <Evidence />
      <Close />
      <ClawdGuide section={active} />
      <MakerGuide section={active} />
    </main>
  )
}
