/** Synapse brand mark — flat junction matching the iOS AppIcon. */
export function SynapseMark({ className = 'h-7 w-7' }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 32 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden
    >
      <rect width="32" height="32" rx="7" fill="#0A1014" />
      <path
        d="M12.38 16C16.56 19.13 16.41 12.88 21.13 16"
        stroke="#59B8AD"
        strokeWidth="1"
        strokeLinecap="round"
        fill="none"
      />
      <circle cx="11.09" cy="16" r="3.69" fill="#59B8AD" />
      <circle cx="21.88" cy="16" r="2.13" fill="#59B8AD" />
    </svg>
  )
}
