# Global Beldex security operations

## Hosting boundary

Global Beldex is published as a static site on GitHub Pages. GitHub Pages serves the generated HTML, CSS, JavaScript, and other public assets. It does not provide an application server, private server-side code, per-route rate limiting, or configurable origin response headers.

A file named `_headers` is a Cloudflare Pages feature, not a GitHub Pages feature. Do not add it expecting GitHub Pages to apply security headers. If response-header control, a web application firewall (WAF), or bot filtering is required, it must be provided by a reverse proxy in front of the GitHub Pages custom domain or by moving the frontend to a host that supports those features.

The public site and the `github.io` project URL may remain independently reachable. A Cloudflare proxy on the custom domain does not make the GitHub Pages origin private or guarantee that requests cannot bypass the proxy.

## Repository controls

The main branch includes these safeguards:

- Vite production source maps are explicitly disabled.
- The GitHub Pages workflow audits the finished static artifact before upload. It rejects source maps, environment/credential files, private-key material, Supabase secret keys, and Supabase service-role JWTs.
- Unit tests cover the static-artifact audit.
- Gitleaks scans repository history on pushes to `main`.
- CodeQL analyzes JavaScript/TypeScript on pushes, pull requests, and a weekly schedule.
- Dependabot checks npm and GitHub Actions dependencies weekly.
- Existing financial and Supabase security regression workflows continue to run.

The frontend uses a Supabase publishable key. Publishable keys are designed for browser use when Row Level Security and least-privilege grants are correctly configured. Never place a Supabase service-role or secret key in a `VITE_*` variable or any public build artifact.

## Supabase review

The connected production project is `jarzpkwdstahbzvbevrq`.

A live security-advisor review reported:

- No tables with RLS disabled in the advisor results.
- Three internal tables have RLS enabled and no policies; a direct privilege check confirmed that `anon` and `authenticated` cannot SELECT them, while `service_role` can. This is intentionally fail-closed.
- The advisor reported 23 `SECURITY DEFINER` functions executable by authenticated users. A read-only review confirmed that anonymous execution is denied. The customer-facing functions check the authenticated user identity; admin operations check the admin record and/or explicit permission helper. The legacy accrual function always raises an exception because automatic accrual is disabled. Do not blanket-revoke authenticated execution: that would break customer operations and administrator RPCs. Review individual function bodies and grants before changing them.
- Supabase reported that leaked-password protection is disabled. Enable it in the Supabase Dashboard under Authentication password security settings, then re-run the security advisor.

Keep the Supabase API key publishable in the frontend. Keep service-role/secret keys only in trusted server-side environments such as Edge Function secrets.

## Cloudflare edge protection for the custom domain

Cloudflare is not configured by repository files. An account owner must perform the following steps in the Cloudflare and domain registrar dashboards.

1. Add `global-beldex.com` to Cloudflare and review the DNS import before changing nameservers.
2. Export or screenshot every existing DNS record first. Preserve all mail records, including MX, SPF, DKIM, DMARC, and any Namecheap Private Email records. Do not switch nameservers until these records have been copied correctly.
3. Keep the GitHub Pages custom domain configured in repository Pages settings. GitHub's documented apex A records are `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, and `185.199.111.153`. The `www` CNAME should point to `ubnlord.github.io` (not the project path).
4. Initially leave the website A/CNAME records DNS-only (grey cloud) while GitHub validates the custom domain and issues its HTTPS certificate. Confirm GitHub Pages shows HTTPS enabled before testing proxy mode.
5. If enabling Cloudflare proxy (orange cloud) afterward, test the homepage, login, registration, Supabase authentication, callbacks, and all payment-related flows. If GitHub Pages certificate validation or site routing fails, revert to DNS-only. Do not proxy mail records.
6. If proxy mode is working, set Cloudflare SSL/TLS encryption to Full (strict), enable Always Use HTTPS, keep automatic DDoS protection enabled, and enable Bot Fight Mode only after testing legitimate customer and API traffic. Bot challenges can interfere with API and mobile clients.
7. Add carefully scoped WAF rules and rate limits for authentication endpoints only after observing normal traffic. Avoid broad country blocks or rules that challenge every API request.
8. Remember that Cloudflare protection on `global-beldex.com` does not automatically protect the separate Supabase hostname `jarzpkwdstahbzvbevrq.supabase.co`. Supabase RLS, grants, Auth settings, and function authorization remain essential.

## GitHub operator settings

In repository Settings, review:

- Dependabot alerts and security updates are enabled.
- Code scanning is enabled and CodeQL results are visible under Security.
- Secret scanning alerts are enabled where available.
- GitHub Pages custom domain remains `global-beldex.com`, and domain ownership is verified.
- Production publishing remains protected by the workflow's explicit manual authorization input.

## Deployment note

Pushes to `main` run validation and build checks. The current Pages workflow does not publish production automatically on every push: production deployment requires a manual workflow dispatch with `authorize_production_deploy` set to `true`. Do not change this gate without an explicit deployment decision.
