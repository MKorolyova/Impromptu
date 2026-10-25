import Head from "next/head";
import { useRouter } from "next/router";
import type { GetServerSideProps } from "next";
import { useEffect, useState, type CSSProperties, type FormEvent } from "react";

type TestEvent = {
  id: string;
  summary: string | null;
  status: string;
  start: string | null;
  end: string | null;
  allDay: boolean;
  location: string | null;
};

type CalendarLink = {
  syncToken: string | null;
  createdAt: string;
  updatedAt: string;
};

type Notice = { kind: "success" | "error"; text: string } | null;

const API = "/api/dev/google-calendar";

type Props = { initialUserId: string; initialNotice: Notice };

// Local testing only. The Google callback returns here with ?userId=…&connected=1 or &error=….
export const getServerSideProps: GetServerSideProps<Props> = async ({ query }) => {
  if (process.env.NODE_ENV === "production") return { notFound: true };
  const pick = (value: unknown) => (typeof value === "string" ? value : "");
  const error = pick(query.error);
  const initialNotice: Notice = error
    ? { kind: "error", text: error }
    : query.connected
      ? { kind: "success", text: "Google Calendar connected and saved. Load events to test it." }
      : null;
  return { props: { initialUserId: pick(query.userId), initialNotice } };
};

async function readError(response: Response): Promise<string> {
  const body = await response.json().catch(() => null);
  return body?.error?.message ?? `Request failed (${response.status})`;
}

function formatWhen(event: TestEvent): string {
  if (!event.start) return "No time";
  if (event.allDay) return `${event.start} · all day`;
  const start = new Date(event.start);
  const end = event.end ? new Date(event.end) : null;
  const day = start.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
  const time = (d: Date) => d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  return `${day} · ${time(start)}${end ? ` – ${time(end)}` : ""}`;
}

export default function GoogleCalendarTest({ initialUserId, initialNotice }: Props) {
  const router = useRouter();
  const [userId, setUserId] = useState(initialUserId);
  const [notice, setNotice] = useState<Notice>(initialNotice);
  const [busy, setBusy] = useState<null | "user" | "events" | "disconnect">(null);
  const [events, setEvents] = useState<TestEvent[] | null>(null);
  const [link, setLink] = useState<CalendarLink | null>(null);
  const [form, setForm] = useState({
    email: "",
    firstName: "Test",
    lastName: "User",
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  });

  // Keep the user in the URL so a reload keeps it; drop the one-time redirect flags.
  useEffect(() => {
    const query = userId ? { userId } : {};
    router.replace({ pathname: "/google-calendar-test", query }, undefined, { shallow: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  async function createUser(e: FormEvent) {
    e.preventDefault();
    setBusy("user");
    setNotice(null);
    try {
      const response = await fetch(`${API}/test-user`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(form),
      });
      if (!response.ok) throw new Error(await readError(response));
      const { user } = await response.json();
      setUserId(user.id);
      setEvents(null);
      setLink(null);
      setNotice({ kind: "success", text: `Test user created for ${user.email}. Now connect Google.` });
    } catch (error) {
      setNotice({ kind: "error", text: (error as Error).message });
    } finally {
      setBusy(null);
    }
  }

  async function loadEvents() {
    setBusy("events");
    setNotice(null);
    try {
      const response = await fetch(`${API}/events?userId=${encodeURIComponent(userId)}`);
      if (!response.ok) throw new Error(await readError(response));
      const body = await response.json();
      setEvents(body.events);
      setLink(body.link);
    } catch (error) {
      setEvents(null);
      setNotice({ kind: "error", text: (error as Error).message });
    } finally {
      setBusy(null);
    }
  }

  async function disconnect() {
    setBusy("disconnect");
    setNotice(null);
    try {
      const response = await fetch(`${API}/disconnect`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userId }),
      });
      if (!response.ok) throw new Error(await readError(response));
      setEvents(null);
      setLink(null);
      setNotice({ kind: "success", text: "Disconnected. The saved connection was deleted." });
    } catch (error) {
      setNotice({ kind: "error", text: (error as Error).message });
    } finally {
      setBusy(null);
    }
  }

  const hasUser = /^[0-9a-f-]{36}$/i.test(userId);

  return (
    <>
      <Head>
        <title>Google Calendar test</title>
      </Head>
      <main style={styles.page}>
        <h1 style={styles.title}>Google Calendar test</h1>
        <p style={styles.muted}>Development only. Connects a Google account, saves it to the database, and reads the next 7 days.</p>

        {notice && (
          <p role="status" style={{ ...styles.notice, ...(notice.kind === "error" ? styles.error : styles.success) }}>
            {notice.text}
          </p>
        )}

        <section style={styles.card}>
          <h2 style={styles.step}>1. User</h2>
          <form onSubmit={createUser} style={styles.grid}>
            <label style={styles.label}>
              Email
              <input style={styles.input} type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="you@example.com" />
            </label>
            <label style={styles.label}>
              Timezone
              <input style={styles.input} required value={form.timezone} onChange={(e) => setForm({ ...form, timezone: e.target.value })} />
            </label>
            <label style={styles.label}>
              First name
              <input style={styles.input} required value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} />
            </label>
            <label style={styles.label}>
              Last name
              <input style={styles.input} required value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} />
            </label>
            <button style={styles.button} disabled={busy !== null}>
              {busy === "user" ? "Creating…" : "Create test user"}
            </button>
          </form>
          <label style={{ ...styles.label, marginTop: 16 }}>
            Or use an existing user ID
            <input style={styles.input} value={userId} onChange={(e) => setUserId(e.target.value.trim())} placeholder="00000000-0000-0000-0000-000000000000" />
          </label>
        </section>

        <section style={{ ...styles.card, ...(hasUser ? null : styles.disabled) }}>
          <h2 style={styles.step}>2. Connect Google</h2>
          <p style={styles.muted}>You will be sent to Google to allow read-only calendar access, then brought back here.</p>
          <div style={styles.row}>
            <a
              style={{ ...styles.button, ...(hasUser && busy === null ? null : styles.buttonDisabled) }}
              href={hasUser ? `${API}/connect?userId=${encodeURIComponent(userId)}` : undefined}
              aria-disabled={!hasUser}
            >
              Connect Google Calendar
            </a>
            <button style={styles.secondary} onClick={disconnect} disabled={!hasUser || busy !== null}>
              {busy === "disconnect" ? "Disconnecting…" : "Disconnect"}
            </button>
          </div>
        </section>

        <section style={{ ...styles.card, ...(hasUser ? null : styles.disabled) }}>
          <h2 style={styles.step}>3. Read events</h2>
          <button style={styles.button} onClick={loadEvents} disabled={!hasUser || busy !== null}>
            {busy === "events" ? "Loading…" : "Load next 7 days"}
          </button>
          {link && (
            <p style={styles.muted}>
              Saved in database · connected {new Date(link.createdAt).toLocaleString()} · sync token {link.syncToken ? "stored" : "not stored"}
            </p>
          )}
          {events && events.length === 0 && <p style={styles.muted}>No events in the next 7 days.</p>}
          {events && events.length > 0 && (
            <ul style={styles.list}>
              {events.map((event) => (
                <li key={event.id} style={styles.event}>
                  <strong>{event.summary ?? "(No title)"}</strong>
                  <span style={styles.muted}>{formatWhen(event)}{event.location ? ` · ${event.location}` : ""}</span>
                  {event.status !== "confirmed" && <span style={styles.badge}>{event.status}</span>}
                </li>
              ))}
            </ul>
          )}
        </section>
      </main>
    </>
  );
}

const styles: Record<string, CSSProperties> = {
  page: { maxWidth: 720, margin: "0 auto", padding: "40px 16px", fontFamily: "system-ui, sans-serif", color: "#1a1a1a" },
  title: { fontSize: 28, margin: "0 0 4px" },
  muted: { color: "#666", fontSize: 14, margin: "8px 0" },
  card: { border: "1px solid #e3e3e3", borderRadius: 12, padding: 20, marginTop: 16, background: "#fff" },
  disabled: { opacity: 0.5 },
  step: { fontSize: 18, margin: "0 0 12px" },
  grid: { display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12, alignItems: "end" },
  label: { display: "flex", flexDirection: "column", gap: 4, fontSize: 13, fontWeight: 500 },
  input: { padding: "8px 10px", border: "1px solid #ccc", borderRadius: 8, fontSize: 14 },
  row: { display: "flex", gap: 8, flexWrap: "wrap" },
  button: { padding: "9px 16px", border: "none", borderRadius: 8, background: "#1a73e8", color: "#fff", fontSize: 14, cursor: "pointer", textDecoration: "none", display: "inline-block" },
  buttonDisabled: { pointerEvents: "none", opacity: 0.5 },
  secondary: { padding: "9px 16px", border: "1px solid #ccc", borderRadius: 8, background: "#fff", fontSize: 14, cursor: "pointer" },
  notice: { padding: "10px 14px", borderRadius: 8, fontSize: 14 },
  success: { background: "#e6f4ea", color: "#137333" },
  error: { background: "#fce8e6", color: "#c5221f" },
  list: { listStyle: "none", padding: 0, margin: "12px 0 0", display: "flex", flexDirection: "column", gap: 8 },
  event: { display: "flex", flexDirection: "column", gap: 2, padding: "10px 12px", border: "1px solid #eee", borderRadius: 8 },
  badge: { alignSelf: "flex-start", fontSize: 12, padding: "1px 8px", borderRadius: 999, background: "#fef7e0", color: "#b06000" },
};
