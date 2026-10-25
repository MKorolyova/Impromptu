import { sql } from "drizzle-orm";
import { ACTIVITIES } from "../constants/activities.ts";
import { closeDb, withTransaction } from "./index.ts";
import { activities } from "./schema.ts";

async function seedStandardActivities(): Promise<void> {
  await withTransaction(async (tx) => {
    await tx
      .insert(activities)
      .values(
        ACTIVITIES.map((activity) => ({
          name: activity.name,
          defaultDurationMinutes: activity.defaultDurationMinutes,
        })),
      )
      .onConflictDoUpdate({
        target: activities.name,
        targetWhere: sql`${activities.ownerId} IS NULL`,
        set: { defaultDurationMinutes: sql`excluded.default_duration_minutes` },
      });
  });
  console.log(`Seeded ${ACTIVITIES.length} standard activities`);
}

try {
  await seedStandardActivities();
} finally {
  await closeDb();
}
