import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { Avatar, readProfilePhoto } from "@/components/layout/avatar";
import { toast, toastError } from "@/components/layout/toast";
import { Button } from "@/components/ui/button";
import { FieldLabel, Input } from "@/components/ui/input";
import { COUNTRIES } from "@/lib/platform/catalog";
import { copy } from "@/lib/platform/i18n";
import { usePlatform } from "@/lib/platform/store";
import { updateCloudPassword } from "@/lib/supabase/auth";

export const Route = createFileRoute("/app/profile")({ component: ProfilePage });

function ProfilePage() {
  const user = usePlatform((s) => s.user);
  const updateProfile = usePlatform((s) => s.updateProfile);
  const changePassword = usePlatform((s) => s.changePassword);
  const lang = usePlatform((s) => s.lang);
  const t = copy[lang];
  const [form, setForm] = useState({
    name: user?.name ?? "",
    username: user?.username ?? "",
    phone: user?.phone ?? "",
    country: user?.country ?? "",
  });
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  const onPhoto = async (file: File | undefined) => {
    if (!file) return;
    const avatar = await readProfilePhoto(file);
    if (!avatar) {
      toast(t.photoTooBig);
      return;
    }
    updateProfile({ avatar });
    toast(t.photoUpdated);
  };

  return (
    <div className="mx-auto max-w-[480px] px-4 pb-[100px] pt-4">
      <h2 className="text-xl font-bold">{t.profileTitle}</h2>
      <div className="mt-6 rounded-lg border border-line bg-elevated p-5">
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            className="relative shrink-0"
            aria-label={t.updatePhoto}
          >
            <Avatar name={user?.name} src={user?.avatar} className="size-16 text-lg" />
          </button>
          <div className="min-w-0">
            <div className="truncate font-semibold">{user?.name}</div>
            <div className="truncate text-xs text-subtle">{user?.email}</div>
            <div className="mt-2 flex flex-wrap gap-2">
              <Button type="button" size="sm" variant="secondary" onClick={() => fileRef.current?.click()}>
                {t.updatePhoto}
              </Button>
              {user?.avatar && (
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    updateProfile({ avatar: undefined });
                    toast(t.photoUpdated);
                  }}
                >
                  {t.removePhoto}
                </Button>
              )}
            </div>
          </div>
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0];
              e.target.value = "";
              void onPhoto(file);
            }}
          />
        </div>
        <div className="mt-6 space-y-4">
          <div>
            <FieldLabel>{t.fullname}</FieldLabel>
            <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </div>
          <div>
            <FieldLabel>{t.username}</FieldLabel>
            <Input
              value={form.username}
              onChange={(e) => setForm({ ...form, username: e.target.value })}
            />
          </div>
          <div>
            <FieldLabel>{t.phone}</FieldLabel>
            <Input
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value })}
            />
          </div>
          <div>
            <FieldLabel>{t.country}</FieldLabel>
            <select
              value={form.country}
              onChange={(e) => setForm({ ...form, country: e.target.value })}
              className="mt-1 w-full rounded-md border border-line-strong bg-elevated px-4 py-3 text-sm outline-none focus:border-accent"
            >
              <option value="">{t.selectCountry}</option>
              {COUNTRIES.map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
          </div>
          <Button
            className="w-full"
            onClick={() => {
              updateProfile({
                name: form.name,
                username: form.username,
                phone: form.phone,
                country: form.country,
              });
              toast(t.profileSaved);
            }}
          >
            {t.saveChanges}
          </Button>
        </div>
      </div>
      <div className="mt-4 rounded-lg border border-line bg-elevated p-5">
        <div className="font-semibold">{t.passwordBlock}</div>
        <p className="mt-1 text-xs text-subtle">{t.passwordHint}</p>
        <div className="mt-4 space-y-4">
          <div>
            <FieldLabel>{t.currentPassword}</FieldLabel>
            <Input
              type="password"
              value={current}
              onChange={(e) => setCurrent(e.target.value)}
            />
          </div>
          <div>
            <FieldLabel>{t.newPassword}</FieldLabel>
            <Input type="password" value={next} onChange={(e) => setNext(e.target.value)} />
          </div>
          <Button
            className="w-full"
            variant="secondary"
            onClick={() => {
              void (async () => {
                const cloud = await updateCloudPassword(next);
                if (cloud === null) {
                  setCurrent("");
                  setNext("");
                  toast(t.passwordUpdated);
                  return;
                }
                if (cloud !== "no-session") {
                  toast(cloud);
                  return;
                }
                const err = changePassword(current, next);
                if (err) {
                  toastError(err);
                  return;
                }
                setCurrent("");
                setNext("");
                toast(t.passwordUpdated);
              })();
            }}
          >
            {t.updatePassword}
          </Button>
        </div>
      </div>
    </div>
  );
}
