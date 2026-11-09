import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { auditPagesOutput } from "./audit-pages-output.mjs";

function withOutput(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "gb-pages-audit-"));
  try {
    run(directory);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

test("accepts ordinary public static assets", () => {
  withOutput((directory) => {
    fs.writeFileSync(path.join(directory, "index.html"), "<!doctype html><title>Global Beldex</title>");
    fs.writeFileSync(path.join(directory, "app.js"), "console.log('public client bundle');");
    assert.deepEqual(auditPagesOutput(directory), []);
  });
});

test("rejects source maps and private configuration files", () => {
  withOutput((directory) => {
    fs.writeFileSync(path.join(directory, "app.js.map"), "{}");
    fs.writeFileSync(path.join(directory, ".env.production"), "SUPABASE_SERVICE_ROLE_KEY=not-real");
    const violations = auditPagesOutput(directory);
    assert.ok(violations.some((item) => item.includes("source maps")));
    assert.ok(violations.some((item) => item.includes("forbidden secret/configuration file")));
  });
});

test("rejects private keys and server-only Supabase secrets", () => {
  withOutput((directory) => {
    fs.writeFileSync(
      path.join(directory, "bundle.js"),
      "const key = '-----BEGIN PRIVATE KEY-----'; const SUPABASE_SERVICE_ROLE_KEY = 'hidden';",
    );
    const violations = auditPagesOutput(directory);
    assert.ok(violations.some((item) => item.includes("private-key material")));
    assert.ok(violations.some((item) => item.includes("server-only Supabase secret")));
  });
});

test("rejects a Supabase service-role JWT by its decoded role claim", () => {
  withOutput((directory) => {
    const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
    const payload = Buffer.from(JSON.stringify({ role: "service_role" })).toString("base64url");
    const token = `${header}.${payload}.signature123456789`;
    fs.writeFileSync(path.join(directory, "bundle.js"), `const leaked = "${token}";`);
    assert.ok(auditPagesOutput(directory).some((item) => item.includes("service-role JWT")));
  });
});
