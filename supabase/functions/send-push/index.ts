// Called by the DB triggers in
// supabase/migrations/20260815150000_push_notifications.sql (expense split
// insert, pet-hunger cron check). The caller only ever sends IDs — the
// actual notification text is fetched here with the service-role key, so
// a leaked anon key (already public, ships in the app) can't be used to
// inject arbitrary push content.
import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FIREBASE_SERVICE_ACCOUNT = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
const serviceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
const projectId = serviceAccount.project_id as string;

const auth = new GoogleAuth({
  credentials: serviceAccount,
  scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
});

async function fcmAccessToken(): Promise<string> {
  const client = await auth.getClient();
  const { token } = await client.getAccessToken();
  if (!token) throw new Error("failed to mint FCM access token");
  return token;
}

type Payload =
  | { type: "expense_split"; expense_id: string; user_id: string }
  | { type: "pet_hungry"; user_id: string; food_key: "fish" | "treats" | "dry_food" }
  | { type: "friend_remind"; user_id: string; reminder_user_id: string; amount: number; pet_name: string }
  | { type: "streak_milestone"; user_id: string; streak_days: number };

async function notificationFor(payload: Payload): Promise<{ title: string; body: string } | null> {
  if (payload.type === "expense_split") {
    const { data: expense } = await admin
      .from("expenses")
      .select("description, amount, paid_by")
      .eq("id", payload.expense_id)
      .maybeSingle();
    if (!expense) return null;
    const { data: payer } = await admin
      .from("public_profiles")
      .select("name")
      .eq("id", expense.paid_by)
      .maybeSingle();
    const payerName = payer?.name ?? "Someone";
    return {
      title: "New expense",
      body: `${payerName} added you to "${expense.description}" — ₹${expense.amount}`,
    };
  }

  if (payload.type === "friend_remind") {
    const { data: reminder } = await admin
      .from("public_profiles")
      .select("name")
      .eq("id", payload.reminder_user_id)
      .maybeSingle();
    const reminderName = reminder?.name ?? "Someone";
    return {
      title: "Reminder",
      body: `${reminderName} reminded you about ₹${payload.amount.toFixed(2)} for ${payload.pet_name}`,
    };
  }

  if (payload.type === "streak_milestone") {
    const { data: pet } = await admin
      .from("pets")
      .select("name")
      .eq("user_id", payload.user_id)
      .maybeSingle();
    return {
      title: "🔥 7-day streak!",
      body: `${pet?.name ?? "Your cat"} loves the routine — keep it going.`,
    };
  }

  const petHungryCopy: Record<"fish" | "treats" | "dry_food", { title: string; body: (name: string) => string }> = {
    fish: { title: "Fish time!", body: (name) => `${name} is ready for fish.` },
    treats: { title: "Treat time!", body: (name) => `${name} could use a treat.` },
    dry_food: { title: "Meal time!", body: (name) => `${name} is hungry for dry food.` },
  };

  const { data: pet } = await admin
    .from("pets")
    .select("name")
    .eq("user_id", payload.user_id)
    .maybeSingle();
  const copy = petHungryCopy[payload.food_key];
  return { title: copy.title, body: copy.body(pet?.name ?? "Your cat") };
}

Deno.serve(async (req) => {
  const payload = (await req.json()) as Payload;

  const notification = await notificationFor(payload);
  if (!notification) return new Response("ok", { status: 200 });

  const { data: tokens } = await admin
    .from("device_tokens")
    .select("token")
    .eq("user_id", payload.user_id);
  if (!tokens || tokens.length === 0) return new Response("ok", { status: 200 });

  const accessToken = await fcmAccessToken();
  const staleTokens: string[] = [];

  await Promise.all(
    tokens.map(async ({ token }) => {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            message: {
              token,
              notification,
              data: {
                type: payload.type,
                ...(payload.type === "pet_hungry" ? { food_key: payload.food_key } : {}),
              },
            },
          }),
        },
      );
      if (res.status === 404 || res.status === 400) {
        // UNREGISTERED / invalid-argument almost always means the token is
        // dead (app uninstalled, token rotated) — stop paying to retry it.
        const body = await res.text();
        if (body.includes("UNREGISTERED") || body.includes("INVALID_ARGUMENT")) {
          staleTokens.push(token);
        }
      }
    }),
  );

  if (staleTokens.length > 0) {
    await admin.from("device_tokens").delete().in("token", staleTokens);
  }

  return new Response("ok", { status: 200 });
});
