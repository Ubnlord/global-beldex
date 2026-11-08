import { createRouter } from "@tanstack/react-router";
import { AppErrorComponent } from "@/lib/error-component";
import { routeTree } from "./routeTree.gen";

export function getRouter() {
  return createRouter({
    routeTree,
    // Keep TanStack navigation aligned with Vite's GitHub Pages project path.
    basepath: import.meta.env.BASE_URL.replace(/\\/$/, "") || "/",
    defaultErrorComponent: AppErrorComponent,
  });
}
