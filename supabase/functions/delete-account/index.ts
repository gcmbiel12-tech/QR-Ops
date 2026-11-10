import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function respond(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function readDefaultKey(variable: string): string | null {
  const raw = Deno.env.get(variable);
  if (!raw) return null;
  try {
    const keys = JSON.parse(raw) as Record<string, unknown>;
    return typeof keys.default === "string" ? keys.default : null;
  } catch {
    return null;
  }
}

function readRecentAuthTime(token: string): number | null {
  const payloadPart = token.split(".")[1];
  if (!payloadPart) return null;
  try {
    const base64 = payloadPart.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    const payload = JSON.parse(atob(padded)) as { auth_time?: unknown };
    return typeof payload.auth_time === "number" ? payload.auth_time : null;
  } catch {
    return null;
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond(405, { success: false, code: "method_not_allowed" });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return respond(401, { success: false, code: "missing_session" });
  }

  const token = authorization.slice("Bearer ".length);
  try {
    // The Edge Runtime validates the JWT before invoking this function.
    // Require a recent login so a stale session alone cannot delete an account.
    const authTime = readRecentAuthTime(token);
    if (
      typeof authTime !== "number" ||
      Date.now() / 1000 - authTime > 5 * 60 ||
      authTime > Date.now() / 1000
    ) {
      return respond(401, {
        success: false,
        code: "reauthentication_required",
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey =
      readDefaultKey("SUPABASE_PUBLISHABLE_KEYS") ??
      Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey =
      readDefaultKey("SUPABASE_SECRET_KEYS") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      console.error("Account deletion function is missing server configuration.");
      return respond(500, { success: false, code: "server_not_configured" });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await userClient.auth.getUser();
    if (error || !data.user) {
      return respond(401, { success: false, code: "invalid_session" });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(
      data.user.id,
    );
    if (deleteError) {
      console.error("Account deletion failed:", deleteError.message);
      return respond(500, { success: false, code: "deletion_failed" });
    }

    return respond(200, { success: true });
  } catch (error) {
    console.error("Account deletion request failed:", error);
    return respond(500, { success: false, code: "internal_error" });
  }
});
