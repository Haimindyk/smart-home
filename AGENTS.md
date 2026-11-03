<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

# Source control and deployments

- `Haimindyk/smart-home` on GitHub is the sole source of application and server code.
- Make every change on a feature branch, commit it, and open a pull request into `main`.
- Deployments may happen only as a consequence of merging a pull request into `main`.
- Validate locally before merging. Do not create branch/PR preview deployments.
- Do not upload local files directly to Vercel or Supabase, run manual deploys or
  redeployments, promote an old deployment, or push directly to `main`.
- Release only the exact Git commit produced by the merge, through the configured
  Git integration or a merge-triggered release workflow. Never treat deployment
  files as the ongoing source of truth or edit code in a hosting service.
- Keep credentials in the hosting services or CI secrets; never commit them.
