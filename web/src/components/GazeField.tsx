import { useEffect, useMemo, useRef } from 'react'
import * as THREE from 'three'
import {
  isKineticModule,
  octantLabel,
  type ParsedModule,
  type TrialWithGaze,
} from '../types/session'

interface GazeFieldProps {
  trial: TrialWithGaze | null
  scrubMs: number
  module: ParsedModule
}

/** 3×3 legacy pad positions (vision / legacy). */
const CELL_POSITIONS: [number, number, number][] = (() => {
  const out: [number, number, number][] = []
  for (let row = 0; row < 3; row++) {
    for (let col = 0; col < 3; col++) {
      out.push([(col - 1) * 1.1, (1 - row) * 1.1, 0])
    }
  }
  return out
})()

/** 8 clock spokes: 12, 1:30, 3, … 10:30 (octant 0..7). */
const OCTANT_POSITIONS: [number, number, number][] = Array.from({ length: 8 }, (_, i) => {
  const angle = (i * Math.PI) / 4 - Math.PI / 2
  const r = 1.55
  return [Math.cos(angle) * r, Math.sin(angle) * r, 0]
})

export function GazeField({ trial, scrubMs, module }: GazeFieldProps) {
  const kinetic = isKineticModule(module)
  const mountRef = useRef<HTMLDivElement>(null)
  const stateRef = useRef<{
    renderer: THREE.WebGLRenderer
    scene: THREE.Scene
    camera: THREE.PerspectiveCamera
    gazeDot: THREE.Mesh
    trail: THREE.Line
    trailGeom: THREE.BufferGeometry
    heatSprites: THREE.Mesh[]
    targets: THREE.Mesh[]
    detectedRing: THREE.Mesh
    frame: number
  } | null>(null)

  const heatPoints = useMemo(() => {
    if (!trial?.gaze) return [] as { x: number; y: number; weight: number }[]
    return trial.gaze.samples.map((s) => ({
      x: s.x * 2.8,
      y: s.y * 2.8,
      weight: 1,
    }))
  }, [trial])

  useEffect(() => {
    const mount = mountRef.current
    if (!mount) return

    const scene = new THREE.Scene()
    scene.background = new THREE.Color('#070b10')
    scene.fog = new THREE.Fog('#070b10', 6, 14)

    const camera = new THREE.PerspectiveCamera(
      42,
      mount.clientWidth / Math.max(mount.clientHeight, 1),
      0.1,
      100,
    )
    camera.position.set(0, 0.2, 5.2)

    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(mount.clientWidth, mount.clientHeight)
    mount.appendChild(renderer.domElement)

    const ambient = new THREE.AmbientLight(0x6b8299, 0.55)
    scene.add(ambient)
    const key = new THREE.DirectionalLight(0x3dffc4, 0.65)
    key.position.set(2, 3, 4)
    scene.add(key)

    const grid = new THREE.GridHelper(6, 12, 0x1e2d3d, 0x121c28)
    grid.rotation.x = Math.PI / 2
    grid.position.z = -0.4
    scene.add(grid)

    if (kinetic) {
      const ring = new THREE.Mesh(
        new THREE.RingGeometry(1.35, 1.75, 64),
        new THREE.MeshBasicMaterial({
          color: 0x1e2d3d,
          transparent: true,
          opacity: 0.55,
          side: THREE.DoubleSide,
        }),
      )
      scene.add(ring)
    }

    const positions = kinetic ? OCTANT_POSITIONS : CELL_POSITIONS
    const targets: THREE.Mesh[] = []
    positions.forEach((pos, i) => {
      const geo = kinetic
        ? new THREE.CircleGeometry(0.22, 24)
        : new THREE.BoxGeometry(0.55, 0.55, 0.08)
      const mat = new THREE.MeshStandardMaterial({
        color: 0x1e2d3d,
        emissive: 0x0d141c,
        metalness: 0.2,
        roughness: 0.55,
      })
      const mesh = new THREE.Mesh(geo, mat)
      mesh.position.set(...pos)
      mesh.userData.cell = i
      scene.add(mesh)
      targets.push(mesh)

      if (!kinetic) {
        const edge = new THREE.LineSegments(
          new THREE.EdgesGeometry(geo),
          new THREE.LineBasicMaterial({ color: 0x3dffc4, transparent: true, opacity: 0.35 }),
        )
        edge.position.copy(mesh.position)
        scene.add(edge)
      }
    })

    const detectedRing = new THREE.Mesh(
      new THREE.RingGeometry(0.28, 0.36, 32),
      new THREE.MeshBasicMaterial({
        color: 0xff3b4e,
        transparent: true,
        opacity: 0,
        side: THREE.DoubleSide,
      }),
    )
    detectedRing.position.z = 0.05
    scene.add(detectedRing)

    const gazeDot = new THREE.Mesh(
      new THREE.SphereGeometry(0.08, 16, 16),
      new THREE.MeshStandardMaterial({
        color: 0xff3b4e,
        emissive: 0xff3b4e,
        emissiveIntensity: 0.8,
      }),
    )
    scene.add(gazeDot)

    const trailGeom = new THREE.BufferGeometry()
    const trail = new THREE.Line(
      trailGeom,
      new THREE.LineBasicMaterial({ color: 0x4da3ff, transparent: true, opacity: 0.7 }),
    )
    scene.add(trail)

    const heatSprites: THREE.Mesh[] = []
    for (let i = 0; i < 80; i++) {
      const heat = new THREE.Mesh(
        new THREE.CircleGeometry(0.12, 16),
        new THREE.MeshBasicMaterial({
          color: 0xf0b429,
          transparent: true,
          opacity: 0,
          depthWrite: false,
        }),
      )
      heat.position.z = 0.05
      scene.add(heat)
      heatSprites.push(heat)
    }

    const onResize = () => {
      if (!mount) return
      const w = mount.clientWidth
      const h = mount.clientHeight
      camera.aspect = w / Math.max(h, 1)
      camera.updateProjectionMatrix()
      renderer.setSize(w, h)
    }
    window.addEventListener('resize', onResize)

    let frame = 0
    const tick = () => {
      frame = requestAnimationFrame(tick)
      renderer.render(scene, camera)
    }
    tick()

    stateRef.current = {
      renderer,
      scene,
      camera,
      gazeDot,
      trail,
      trailGeom,
      heatSprites,
      targets,
      detectedRing,
      frame,
    }

    return () => {
      cancelAnimationFrame(frame)
      window.removeEventListener('resize', onResize)
      renderer.dispose()
      mount.removeChild(renderer.domElement)
      stateRef.current = null
    }
  }, [kinetic])

  useEffect(() => {
    const state = stateRef.current
    if (!state) return

    state.targets.forEach((mesh, i) => {
      const mat = mesh.material as THREE.MeshStandardMaterial
      const active = kinetic
        ? trial?.targetOctant === i
        : trial?.targetCell === i
      mat.emissive = new THREE.Color(active ? 0x3dffc4 : 0x0d141c)
      mat.emissiveIntensity = active ? 0.9 : 0.2
      mat.color = new THREE.Color(active ? 0x1a3d34 : 0x1e2d3d)
    })

    if (kinetic && trial?.detectedOctant != null) {
      const pos = OCTANT_POSITIONS[trial.detectedOctant]
      state.detectedRing.position.x = pos[0]
      state.detectedRing.position.y = pos[1]
      const mat = state.detectedRing.material as THREE.MeshBasicMaterial
      mat.opacity = 0.95
      mat.color = new THREE.Color(trial.spatialMatch ? 0x3dffc4 : 0xff3b4e)
    } else {
      ;(state.detectedRing.material as THREE.MeshBasicMaterial).opacity = 0
    }

    state.heatSprites.forEach((sprite, i) => {
      const mat = sprite.material as THREE.MeshBasicMaterial
      const pt = heatPoints[i]
      if (!pt || kinetic) {
        mat.opacity = 0
        return
      }
      sprite.position.x = pt.x
      sprite.position.y = pt.y
      mat.opacity = 0.08 + (i / Math.max(heatPoints.length, 1)) * 0.25
    })

    if (kinetic || !trial?.gaze || trial.gaze.samples.length === 0) {
      state.gazeDot.visible = false
      state.trailGeom.setAttribute(
        'position',
        new THREE.Float32BufferAttribute(new Float32Array(0), 3),
      )
      return
    }

    state.gazeDot.visible = true
    const samples = trial.gaze.samples
    const visible = samples.filter((s) => s.dt <= scrubMs)
    const current = visible[visible.length - 1] ?? samples[0]

    state.gazeDot.position.set(current.x * 2.8, current.y * 2.8, 0.35)

    const positions = new Float32Array(visible.length * 3)
    visible.forEach((s, i) => {
      positions[i * 3] = s.x * 2.8
      positions[i * 3 + 1] = s.y * 2.8
      positions[i * 3 + 2] = 0.3
    })
    state.trailGeom.setAttribute('position', new THREE.BufferAttribute(positions, 3))
    state.trailGeom.computeBoundingSphere()
  }, [trial, scrubMs, heatPoints, kinetic])

  const subtitle = (() => {
    if (!trial) return 'No trial'
    if (kinetic) {
      const match =
        trial.spatialMatch == null ? '' : trial.spatialMatch ? ' · match' : ' · miss'
      return `Trial ${trial.index} · T ${octantLabel(trial.targetOctant)} → D ${octantLabel(trial.detectedOctant)}${match}`
    }
    const cell = trial.targetCell != null ? `cell ${trial.targetCell}` : 'flash'
    return `Trial ${trial.index} · ${cell}`
  })()

  return (
    <div className="flex h-full min-h-[320px] flex-col rounded-sm border border-line bg-panel/70">
      <div className="flex items-center justify-between border-b border-line px-4 py-2">
        <h2 className="font-display text-sm font-medium tracking-wide text-fog">
          {kinetic ? 'Clock field' : 'Gaze field'}
        </h2>
        <span className="font-mono text-[10px] uppercase tracking-wider text-muted">
          {subtitle}
        </span>
      </div>
      <div ref={mountRef} className="min-h-0 flex-1" />
    </div>
  )
}
