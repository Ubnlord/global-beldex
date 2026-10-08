import type { User } from "@supabase/supabase-js";
import { supabase } from "./client";

export type CloudProfile = {
  email: string;
  username: string;
  fullname: string;
  phone: string;
  country: string;
  ref?: string;
  avatar?: string;
};

function redirectTo(path: string) {
  if (typeof window === "undefined") return undefined;
  return `${window.location.origin}${path}`;
}

export function profileFromUser(user: User | null | undefined): CloudProfile | null {
  const email = user?.email?.trim().toLowerCase();
  if (!email) return null;
  const meta = (user?.user_metadata ?? {}) as Record<string, unknown>;
  const username = String(meta.username || email.split("@")[0]);
  return {
    email,
    username,
    fullname: String(meta.full_name || meta.username || username),
    phone: String(meta.phone || ""),
    country: String(meta.country || ""),
    ref: meta.ref ? String(meta.ref) : undefined,
    avatar: meta.avatar_url ? String(meta.avatar_url) : undefined,
  };
}

function friendly(message: string) {
  const m = message.toLowerCase();
  if (m.includes("already registered") || m.includes("already been registered")) {
    return "That email is already registered. Sign in instead.";
  }
  if (m.includes("invalid login") || m.includes("invalid credentials")) {
    return "Email or password is wrong.";
  }
  if (
    m.includes("over_email_send_rate_limit") ||
    m.includes("email rate limit") ||
    m.includes("too many emails")
  ) {
    return "Email sending is temporarily rate-limited. Please wait before trying again. For production, the site administrator must configure custom SMTP in Supabase Auth.";
  }
  if (m.includes("email not confirmed")) {
    return "Confirm your email first. Check the inbox for the link.";
  }
  if (m.includes("password")) {
    return "Use at least 6 characters.";
  }
  return message;
}

export async function signUpAccount(input: CloudProfile & { pass: string }) {
  const { data, error } = await supabase.auth.signUp({
    email: input.email.trim().toLowerCase(),
    password: input.pass,
    options: {
      emailRedirectTo: redirectTo("/auth/confirm"),
      data: {
        username: input.username.trim(),
        full_name: input.fullname.trim() || input.username.trim(),
        phone: input.phone.trim(),
        country: input.country.trim(),
        ref: input.ref?.trim() || "",
      },
    },
  });
  if (error) return { error: friendly(error.message), needsConfirm: false, profile: null };
  const profile = profileFromUser(data.user);
  return { error: null, needsConfirm: !data.session, profile };
}

export async function ensureCloudProfile(profile: CloudProfile) {
  const { error } = await supabase.rpc("ensure_user_profile", {
    p_username: profile.username,
    p_fullname: profile.fullname,
    p_phone: profile.phone,
    p_country: profile.country,
    p_ref: profile.ref || null,
  });
  return error ? friendly(error.message) : null;
}

export async function updateCloudProfile(profile: CloudProfile) {
  const { error } = await supabase.rpc("update_user_profile", {
    p_username: profile.username,
    p_fullname: profile.fullname,
    p_phone: profile.phone,
    p_country: profile.country,
    p_avatar_url: profile.avatar || null,
  });
  if (error) return friendly(error.message);

  // Keep the Auth metadata aligned with the profile used during sign-in.
  const { error: authError } = await supabase.auth.updateUser({
    data: {
      username: profile.username,
      full_name: profile.fullname,
      phone: profile.phone,
      country: profile.country,
    },
  });
  return authError ? friendly(authError.message) : null;
}

export async function signInAccount(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim().toLowerCase(),
    password,
  });
  if (error) return { error: friendly(error.message), profile: null };
  return { error: null, profile: profileFromUser(data.user) };
}

export async function signOutCloud() {
  await supabase.auth.signOut();
}

export async function sendReset(email: string) {
  const { error } = await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
    redirectTo: redirectTo("/auth/confirm?type=recovery"),
  });
  if (error) return friendly(error.message);
  return null;
}

export async function updateCloudPassword(next: string, currentPassword?: string) {
  const { data } = await supabase.auth.getSession();
  if (!data.session) return "no-session";
  if (!next || next.length < 6) return "Use at least 6 characters.";
  if (currentPassword !== undefined && !currentPassword) return "Enter your current password.";
  const { error } = await supabase.auth.updateUser({
    password: next,
    ...(currentPassword !== undefined ? { current_password: currentPassword } : {}),
  });
  if (error) return friendly(error.message);
  return null;
}

export async function currentProfile() {
  const { data } = await supabase.auth.getSession();
  const base = profileFromUser(data.session?.user);
  if (!base || !data.session) return base;

  const { data: row, error } = await supabase
    .from("user_profile")
    .select("username,fullname,phone,country,avatar_url,referral_code")
    .eq("user_id", data.session.user.id)
    .maybeSingle();

  if (error || !row) return base;
  return {
    ...base,
    username: row.username || base.username,
    fullname: row.fullname || base.fullname,
    phone: row.phone || "",
    country: row.country || "",
    ref: row.referral_code || base.ref,
    avatar: row.avatar_url || undefined,
  };
}

export async function completeAuthRedirect(code: string | null) {
  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) return { error: friendly(error.message), profile: null };
  }
  const profile = await currentProfile();
  if (!profile) {
    return { error: "That link expired. Request a new one from sign in.", profile: null };
  }
  return { error: null, profile };
}
