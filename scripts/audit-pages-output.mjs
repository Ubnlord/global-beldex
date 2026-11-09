import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const TEXT_EXTENSIONS = new Set([
  ".html", ".htm", ".js", ".mjs", ".cjs", ".css", ".json", ".txt",
  ".xml", ".svg", ".webmanifest", ".map",
]);

const FORBIDDEN_FILE = /(?:^|\/)(?:\.env(?:\..*)?|[^/]*\.(?:pem|key|p12|pfx|crt)|credentials[^/]*\.json|service-account[^/]*\.json)$/i;
const PRIVATE_KEY = /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/;
const SECRET_ASSIGNMENT = /\b(?:SUPABASE_SERVICE_ROLE_KEY|SUPABASE_SECRET_KEY)\s*[:=]/i;
const SUPABASE_SECRET = /\bsb_secret_[A-Za-z0-9_-]{10,}/;

function walk(directory, relative = "") {
  const entries = fs.readdirSync(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const rel = relative ? path.posix.join(relative, entry.name) : entry.name;
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(absolute, rel));
    else if (entry.isFile()) files.push({ absolute, relative: rel });
  }
  return files;
}

function isServiceRoleJwt(value) {
  const parts = value.split(".");
  if (parts.length !== 3) return false;
  try {
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    return payload?.role === "service_role";
  } catch {
    return false;
  }
}

export function auditPagesOutput(outputDirectory) {
  const root = path.resolve(outputDirectory);
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
    return [`Pages output directory does not exist: ${root}`];
  }

  const violations = [];
  for (const file of walk(root)) {
    if (FORBIDDEN_FILE.test(file.relative)) {
      violations.push(`${file.relative}: forbidden secret/configuration file in public output`);
      continue;
    }

    if (file.relative.endsWith(".map")) {
      violations.push(`${file.relative}: source maps must not be published`);
      continue;
    }

    if (!TEXT_EXTENSIONS.has(path.extname(file.relative).toLowerCase())) continue;
    const content = fs.readFileSync(file.absolute, "utf8");

    if (PRIVATE_KEY.test(content)) {
      violations.push(`${file.relative}: private-key material detected`);
    }
    if (SECRET_ASSIGNMENT.test(content)) {
      violations.push(`${file.relative}: server-only Supabase secret variable detected`);
    }
    if (SUPABASE_SECRET.test(content)) {
      violations.push(`${file.relative}: Supabase secret key detected`);
    }

    const jwtPattern = /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g;
    for (const match of content.matchAll(jwtPattern)) {
      if (isServiceRoleJwt(match[0])) {
        violations.push(`${file.relative}: Supabase service-role JWT detected`);
        break;
      }
    }
  }

  return violations;
}

const invoked = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invoked) {
  const outputDirectory = process.argv[2] || "pages-site";
  const violations = auditPagesOutput(outputDirectory);
  if (violations.length) {
    console.error("GitHub Pages security audit failed:");
    for (const violation of violations) console.error(`- ${violation}`);
    process.exitCode = 1;
  } else {
    console.log(`GitHub Pages security audit passed: ${path.resolve(outputDirectory)}`);
  }
}
