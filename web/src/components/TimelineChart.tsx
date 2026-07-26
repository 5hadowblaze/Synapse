import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  ReferenceLine,
} from 'recharts'
import { isKineticModule, type Session, type Trial } from '../types/session'

interface TimelineChartProps {
  trials: Trial[]
  session: Session
  selectedIndex: number | null
  onSelect: (index: number) => void
}

export function TimelineChart({
  trials,
  session,
  selectedIndex,
  onSelect,
}: TimelineChartProps) {
  const kinetic = isKineticModule(session.module)

  let runningHits = 0
  let runningN = 0
  const data = trials
    .filter((t) => t.valid)
    .map((t) => {
      if (t.spatialMatch != null) {
        runningN += 1
        if (t.spatialMatch) runningHits += 1
      }
      return {
        index: t.index,
        visualRtMs: t.visualRtMs != null ? Math.round(t.visualRtMs) : null,
        motorRtMs: t.motorRtMs != null ? Math.round(t.motorRtMs) : null,
        arousal: t.arousalIndex != null ? Math.round(t.arousalIndex * 100) : null,
        accuracyPct: runningN > 0 ? Math.round((runningHits / runningN) * 100) : null,
      }
    })

  return (
    <div className="surface-lift flex h-full min-h-[260px] flex-col rounded-sm border border-line bg-panel/70 p-4">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="font-display text-sm font-medium tracking-wide text-fog">
          {kinetic ? 'Motor + spatial timeline' : 'Vision reaction timeline'}
        </h2>
        <div className="flex gap-4 font-mono text-[10px] uppercase tracking-wider text-muted">
          {kinetic ? (
            <>
              <span className="text-motor">● Motor RT</span>
              <span className="text-signal">● Cum. accuracy %</span>
            </>
          ) : (
            <>
              <span className="text-visual">● Visual RT</span>
              <span className="text-signal">● Arousal ×100</span>
            </>
          )}
        </div>
      </div>
      <div className="min-h-0 flex-1">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart
            data={data}
            margin={{ top: 8, right: kinetic ? 36 : 12, left: 0, bottom: 0 }}
            onClick={(state) => {
              const payload = state as {
                activePayload?: Array<{ payload?: { index?: number } }>
              }
              const idx = payload.activePayload?.[0]?.payload?.index
              if (typeof idx === 'number') onSelect(idx)
            }}
          >
            <CartesianGrid stroke="#1e2d3d" strokeDasharray="3 3" />
            <XAxis
              dataKey="index"
              stroke="#6b8299"
              tick={{ fill: '#6b8299', fontSize: 11, fontFamily: 'IBM Plex Mono' }}
              label={{
                value: 'Trial',
                position: 'insideBottomRight',
                offset: -2,
                fill: '#6b8299',
                fontSize: 10,
              }}
            />
            <YAxis
              yAxisId="ms"
              stroke="#6b8299"
              tick={{ fill: '#6b8299', fontSize: 11, fontFamily: 'IBM Plex Mono' }}
              unit="ms"
              width={48}
            />
            {kinetic ? (
              <YAxis
                yAxisId="pct"
                orientation="right"
                domain={[0, 100]}
                stroke="#3dffc4"
                tick={{ fill: '#6b8299', fontSize: 11, fontFamily: 'IBM Plex Mono' }}
                unit="%"
                width={40}
              />
            ) : null}
            <Tooltip
              contentStyle={{
                background: '#0d141c',
                border: '1px solid #1e2d3d',
                borderRadius: 2,
                fontFamily: 'IBM Plex Mono',
                fontSize: 12,
              }}
              labelFormatter={(v) => `Trial ${v}`}
            />
            <Legend wrapperStyle={{ display: 'none' }} />
            {session.baselineGapMs != null ? (
              <ReferenceLine
                yAxisId="ms"
                y={session.baselineGapMs}
                stroke="#3dffc4"
                strokeDasharray="4 4"
                strokeOpacity={0.35}
              />
            ) : null}
            {session.breakPointTrial != null ? (
              <ReferenceLine
                yAxisId="ms"
                x={session.breakPointTrial}
                stroke="#ff3b4e"
                strokeWidth={2}
                label={{
                  value: 'BREAK',
                  fill: '#ff3b4e',
                  fontSize: 10,
                  fontFamily: 'IBM Plex Mono',
                }}
              />
            ) : null}
            {selectedIndex != null ? (
              <ReferenceLine
                yAxisId="ms"
                x={selectedIndex}
                stroke="#9bb0c4"
                strokeOpacity={0.5}
              />
            ) : null}
            {kinetic ? (
              <>
                <Line
                  yAxisId="ms"
                  type="monotone"
                  dataKey="motorRtMs"
                  name="Motor RT"
                  stroke="#f0b429"
                  strokeWidth={2.5}
                  dot={false}
                  activeDot={{ r: 5 }}
                  connectNulls
                />
                <Line
                  yAxisId="pct"
                  type="monotone"
                  dataKey="accuracyPct"
                  name="Accuracy %"
                  stroke="#3dffc4"
                  strokeWidth={2}
                  dot={false}
                  activeDot={{ r: 4 }}
                  connectNulls
                />
              </>
            ) : (
              <>
                <Line
                  yAxisId="ms"
                  type="monotone"
                  dataKey="visualRtMs"
                  name="Visual RT"
                  stroke="#4da3ff"
                  strokeWidth={2.5}
                  dot={false}
                  activeDot={{ r: 5 }}
                  connectNulls
                />
                <Line
                  yAxisId="ms"
                  type="monotone"
                  dataKey="arousal"
                  name="Arousal"
                  stroke="#3dffc4"
                  strokeWidth={2}
                  dot={false}
                  activeDot={{ r: 4 }}
                  connectNulls
                />
              </>
            )}
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}
