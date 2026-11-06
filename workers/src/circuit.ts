// Circuit breaker for external payment/SMS providers.
// Prevents cascading failures when Lipila / Africa's Talking is degraded:
// after N consecutive failures the breaker opens for a cool-down window and
// short-circuits calls with a fast 503 instead of waiting on timeouts.
export type CircuitState = 'closed' | 'open' | 'half_open';

interface CircuitBreaker {
  failures: number;
  lastFailure: number;
  state: CircuitState;
}

const CIRCUITS = new Map<string, CircuitBreaker>();

const FAILURE_THRESHOLD = 5;
const COOL_DOWN_MS = 60 * 1000; // 1 minute
const HALF_OPEN_MAX_CALLS = 3;
let halfOpenCalls = 0;

function getCircuit(name: string): CircuitBreaker {
  let c = CIRCUITS.get(name);
  if (!c) { c = { failures: 0, lastFailure: 0, state: 'closed' }; CIRCUITS.set(name, c); }
  return c;
}

export function canCall(name: string): { allowed: boolean; retryAfterMs?: number } {
  const c = getCircuit(name);
  const now = Date.now();
  if (c.state === 'open') {
    if (now - c.lastFailure > COOL_DOWN_MS) {
      c.state = 'half_open';
      halfOpenCalls = 0;
      return { allowed: true };
    }
    return { allowed: false, retryAfterMs: COOL_DOWN_MS - (now - c.lastFailure) };
  }
  if (c.state === 'half_open') {
    if (halfOpenCalls >= HALF_OPEN_MAX_CALLS) {
      return { allowed: false, retryAfterMs: COOL_DOWN_MS };
    }
    return { allowed: true };
  }
  return { allowed: true };
}

export function recordSuccess(name: string): void {
  const c = getCircuit(name);
  c.failures = 0;
  c.state = 'closed';
  halfOpenCalls = 0;
}

export function recordFailure(name: string): void {
  const c = getCircuit(name);
  c.failures += 1;
  c.lastFailure = Date.now();
  if (c.failures >= FAILURE_THRESHOLD) {
    c.state = 'open';
  }
}

export async function withCircuit<T>(
  name: string,
  fn: () => Promise<T>,
): Promise<T> {
  const gate = canCall(name);
  if (!gate.allowed) {
    const err: any = new Error(`circuit_open:${name}`);
    err.status = 503;
    err.retryAfterMs = gate.retryAfterMs;
    throw err;
  }
  if (getCircuit(name).state === 'half_open') halfOpenCalls += 1;
  try {
    const result = await fn();
    recordSuccess(name);
    return result;
  } catch (e: any) {
    recordFailure(name);
    throw e;
  }
}
