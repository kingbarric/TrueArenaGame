# Cloudflare R2 (SlayHuud art and look snapshots)

Bucket `playhuud-assets` (Western Europe). Test and production share it, and the
same R2 token, for now.

| What | Where in the bucket | Who writes it |
|---|---|---|
| SlayHuud art (content-hashed GLB/PNG/JSON) | `slay/` | `infra/publish-slay-assets-r2.sh` after `npm run build` in `slay-renderer` |
| SlayHuud look snapshots (JPEG) | `slay/looks/<lookId>-<random>.jpg` | the backend (`ObjectStorage`), test and prod alike |

- Phones download art from `SLAY_ASSET_BASE`, currently the public dev URL
  `https://pub-add3eaff74154969a3810cabdb63ef40.r2.dev/slay/`.
- The backend reads and writes snapshots with `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`
  and `R2_SECRET_ACCESS_KEY`. They live in the git-ignored `infra/keys/`
  (`cloudflare-r2.env.local`, and copied into `test.env.local` / `prod.env.local`)
  and in `.env` on the VPS for each stack. Without them snapshots stay in Postgres.
- Snapshot names can't be guessed, but the whole bucket is public through the
  dev URL; the API still decides who may see a look.

## To change later

1. **Custom domain for art.** The `r2.dev` URL is rate-limited and not meant for
   production traffic. Move playhuud.com's DNS (nameservers) to Cloudflare — the
   domain can stay registered at Porkbun — then connect `assets.playhuud.com` to
   the bucket and set `SLAY_ASSET_BASE=https://assets.playhuud.com/slay/` in the
   prod `.env` (and the default in `docker-compose.prod.yml`). No app release needed:
   the app gets the address from the server.
2. **Turn off the public dev URL** once the custom domain serves the art, so the
   bucket is only reachable through it.
3. **Separate prod credentials.** Make a production R2 token (Object Read & Write,
   this bucket only), put it in the VPS `~/truearena/infra/.env` and
   `infra/keys/prod.env.local`, and keep the current token for test. Consider a
   separate bucket for test.
4. **Rotate the current token.** It was pasted into a chat session when it was
   set up.
5. **Publish art before deploying a backend whose manifest names new files**
   (`infra/publish-slay-assets-r2.sh`); it only ever adds files.
