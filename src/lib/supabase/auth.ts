import type { User } from "@supabase/supabase-js";
import { supabase } from "./client";

export type CloudProfile = {
  email: string;
  username: string;
  fullname: string;
  phone: string;
  country: string;
  ref?: string;
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

export async function updateCloudPassword(next: string) {
  const { data } = await supabase.auth.getSession();
  if (!data.session) return "no-session";
  if (!next || next.length < 6) return "Use at least 6 characters.";
  const { error } = await supabase.auth.updateUser({ password: next });
  if (error) return friendly(error.message);
  return null;
}

export async function currentProfile() {
  const { data } = await supabase.auth.getSession();
  return profileFromUser(data.session?.user);
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
