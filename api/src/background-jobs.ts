import { runGoogleCalendarTick } from "@/google-calendar-service/calendar-statuses";

const GOOGLE_CALENDAR_TICK_MS = 60 * 1000;

// Survives Next.js dev reloads, so jobs aren't started twice.
const globalForJobs = globalThis as typeof globalThis & { backgroundJobsStarted?: boolean };

export function startBackgroundJobs(): void {
  if (globalForJobs.backgroundJobsStarted) return;
  globalForJobs.backgroundJobsStarted = true;

  // Every minute: turn calendar events that just started into statuses.
  setInterval(() => {
    runGoogleCalendarTick().catch((error) => console.error("Google Calendar tick failed", error));
  }, GOOGLE_CALENDAR_TICK_MS).unref();
}
