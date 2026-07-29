export interface PollingLoopOptions {
  task: (signal: AbortSignal) => Promise<void>;
  intervalMs: number;
  maxBackoffMs: number;
  now?: () => number;
  schedule?: (callback: () => void | Promise<void>, delayMs: number) => unknown;
  cancel?: (timer: unknown) => void;
}

export interface PollingLoop {
  start(): void;
  pause(): void;
  resume(): void;
  stop(): void;
}

export function createPollingLoop({
  task,
  intervalMs,
  maxBackoffMs,
  now = Date.now,
  schedule = (callback, delayMs) => setTimeout(callback, delayMs),
  cancel = (timer) => clearTimeout(timer as ReturnType<typeof setTimeout>),
}: PollingLoopOptions): PollingLoop {
  let timer: unknown;
  let controller: AbortController | null = null;
  let running = false;
  let paused = false;
  let stopped = false;
  let failures = 0;
  let nextDueAt: number | null = null;

  const cancelTimer = () => {
    if (timer == null) return;
    cancel(timer);
    timer = undefined;
  };

  const scheduleRun = (delayMs: number) => {
    cancelTimer();
    const delay = Math.max(0, delayMs);
    nextDueAt = now() + delay;
    timer = schedule(run, delay);
  };

  const run = async () => {
    timer = undefined;
    if (running || paused || stopped) return;

    running = true;
    controller = new AbortController();
    const activeController = controller;
    let nextDelay = intervalMs;

    try {
      await task(activeController.signal);
      failures = 0;
    } catch {
      if (!activeController.signal.aborted) {
        failures += 1;
        nextDelay = Math.min(intervalMs * 2 ** failures, maxBackoffMs);
      }
    } finally {
      running = false;
      if (controller === activeController) controller = null;
      if (!paused && !stopped) {
        if (activeController.signal.aborted) {
          scheduleRun(Math.max(0, (nextDueAt ?? now()) - now()));
        } else {
          scheduleRun(nextDelay);
        }
      }
    }
  };

  return {
    start() {
      if (stopped || nextDueAt != null || running) return;
      scheduleRun(0);
    },
    pause() {
      if (paused || stopped) return;
      paused = true;
      cancelTimer();
      controller?.abort();
    },
    resume() {
      if (!paused || stopped) return;
      paused = false;
      if (!running) scheduleRun(Math.max(0, (nextDueAt ?? now()) - now()));
    },
    stop() {
      if (stopped) return;
      stopped = true;
      cancelTimer();
      controller?.abort();
    },
  };
}
