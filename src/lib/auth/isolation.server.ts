import { getRequest } from "@tanstack/react-start/server";

export class CrossSiteRequestError extends Error {
  constructor(message = "Cross-site request blocked.") {
    super(message);
    this.name = "CrossSiteRequestError";
  }
}

function firstHeader(req: Request, name: string): string | null {
  return req.headers.get(name)?.split(",")[0]?.trim() || null;
}

export function assertSameSiteRequest(): void {
  const req = getRequest();
  if (!req) return;

  const fetchSite = firstHeader(req, "sec-fetch-site");
  if (fetchSite && !["same-origin", "same-site", "none"].includes(fetchSite)) {
    throw new CrossSiteRequestError("Cross-site request blocked.");
  }

  const host = firstHeader(req, "x-forwarded-host") || firstHeader(req, "host");
  const origin = firstHeader(req, "origin");

  if (origin && host) {
    try {
      const originUrl = new URL(origin);
      const expectedHost = host.split(":")[0].toLowerCase();
      const actualHost = originUrl.hostname.toLowerCase();
      if (actualHost !== expectedHost) {
        throw new CrossSiteRequestError("Cross-origin request blocked.");
      }
      return;
    } catch (error) {
      if (error instanceof CrossSiteRequestError) throw error;
      throw new CrossSiteRequestError("Invalid request origin.");
    }
  }

  const referer = firstHeader(req, "referer");
  if (referer && host) {
    try {
      const refererUrl = new URL(referer);
      const expectedHost = host.split(":")[0].toLowerCase();
      if (refererUrl.hostname.toLowerCase() !== expectedHost) {
        throw new CrossSiteRequestError("Cross-origin request blocked.");
      }
    } catch (error) {
      if (error instanceof CrossSiteRequestError) throw error;
      throw new CrossSiteRequestError("Invalid request referrer.");
    }
  }
}
