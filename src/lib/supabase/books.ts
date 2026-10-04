import type { Book } from "@/lib/platform/store";
import { supabase } from "./client";

type BookRow = {
  available: number | string;
  bdx: number | string;
  locked: number | string;
  profit: number | string;
  bonus: number | string;
  referral_bonus: number | string;
  withdrawn: number | string;
  txs: Book["txs"];
  plans: Book["plans"];
  notices: Book["notices"];
  tickets: Book["tickets"];
};

function num(value: number | string | null | undefined) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function rowToBook(row: BookRow): Book {
  return {
    available: num(row.available),
    bdx: num(row.bdx),
    locked: num(row.locked),
    profit: num(row.profit),
    bonus: num(row.bonus),
    referralBonus: num(row.referral_bonus),
    withdrawn: num(row.withdrawn),
    txs: Array.isArray(row.txs) ? row.txs : [],
    plans: Array.isArray(row.plans) ? row.plans : [],
    notices: Array.isArray(row.notices) ? row.notices : [],
    tickets: Array.isArray(row.tickets) ? row.tickets : [],
  };
}

async function userId() {
  const { data } = await supabase.auth.getSession();
  return data.session?.user.id ?? null;
}

export async function pullCloudBook(): Promise<Book | null> {
  const id = await userId();
  if (!id) return null;
  const { data, error } = await supabase.from("books").select("*").eq("user_id", id).maybeSingle();
  if (error || !data) return null;
  return rowToBook(data as BookRow);
}

export async function pushCloudBook(book: Book) {
  const id = await userId();
  if (!id) return;
  await supabase.from("books").upsert(
    {
      user_id: id,
      available: book.available,
      bdx: book.bdx,
      locked: book.locked,
      profit: book.profit,
      bonus: book.bonus,
      referral_bonus: book.referralBonus,
      withdrawn: book.withdrawn,
      txs: book.txs,
      plans: book.plans,
      notices: book.notices,
      tickets: book.tickets ?? [],
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );
}

let timer: ReturnType<typeof setTimeout> | undefined;
let pending: Book | null = null;

export function scheduleCloudSave(book: Book) {
  pending = book;
  if (timer) clearTimeout(timer);
  timer = setTimeout(() => {
    const next = pending;
    pending = null;
    if (next) void pushCloudBook(next);
  }, 500);
}
