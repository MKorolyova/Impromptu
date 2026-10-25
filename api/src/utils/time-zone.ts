// Time zone math with Intl only. `timeZone` is an IANA name like "America/Chicago".

function wallClock(timeZone: string, date: Date) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    })
      .formatToParts(date)
      .map((part) => [part.type, Number(part.value)]),
  );
  return parts as Record<"year" | "month" | "day" | "hour" | "minute" | "second", number>;
}

// How far the zone's wall clock is ahead of UTC at `date`, in ms.
function offsetMs(timeZone: string, date: Date): number {
  const c = wallClock(timeZone, date);
  return Date.UTC(c.year, c.month - 1, c.day, c.hour, c.minute, c.second) - Math.floor(date.getTime() / 1000) * 1000;
}

// The user's local calendar date, as "YYYY-MM-DD".
export function localDateKey(timeZone: string, date: Date): string {
  const c = wallClock(timeZone, date);
  return `${c.year}-${String(c.month).padStart(2, "0")}-${String(c.day).padStart(2, "0")}`;
}

// The instant the user's local day ends (next local midnight), correct across DST changes.
export function endOfLocalDay(timeZone: string, date: Date): Date {
  const c = wallClock(timeZone, date);
  const midnightAsUtc = Date.UTC(c.year, c.month - 1, c.day + 1);
  let instant = midnightAsUtc - offsetMs(timeZone, new Date(midnightAsUtc));
  // Second pass in case the offset differs at the real instant (DST).
  instant = midnightAsUtc - offsetMs(timeZone, new Date(instant));
  return new Date(instant);
}

// e.g. "Mon 09:30", in the user's zone.
export function localWeekdayAndTime(timeZone: string, date: Date): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(date);
}
