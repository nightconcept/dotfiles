# Personal search: Degoog and SearXNG

Researched 2026-10-12. The intended use is a private search box at `search.solivan.dev` that favors smaller sites and does not expose the host to anonymous search traffic.

## Recommendation

SearXNG has a documented [Marginalia engine](https://docs.searxng.org/dev/engines/online/marginalia.html), plus [engine weights](https://docs.searxng.org/admin/settings/settings_engines.html) and a [Hostnames plugin](https://docs.searxng.org/dev/plugins/hostnames.html) to favor or remove domains. It was the first deployed option.

**Degoog is the selected replacement.** It lets a signed-in admin [block, replace, or score domains from results](https://degoog-org.github.io/docs/using-search.html) and has an optional [local indexer](https://degoog-org.github.io/docs/indexer.html) that recalls results from earlier searches. The indexer does not crawl or discover the web on its own. Degoog describes itself as [stable beta](https://github.com/degoog-org/degoog); it ships with zero search engines until extensions are installed.

Neither product supplies a Kagi-like independent general web index. Both normally [query external engines](https://docs.searxng.org/dev/engines/engine_overview.html) and can only return what those engines expose; changing the front end alone will not eliminate their coverage and ranking biases. Degoog's remembered results and SearXNG's Marginalia source offer partial ways to diversify those results. [Degoog overview](https://degoog-org.github.io/docs/); [SearXNG overview](https://github.com/searxng/searxng).

## Controls worth testing

| Need | SearXNG | Degoog |
| --- | --- | --- |
| Choose sources | Configure/disable engines and set each engine's `weight`; [Marginalia](https://docs.searxng.org/dev/engines/online/marginalia.html) needs an API key, and its optional custom filter needs a key other than `public`. [Engine settings](https://docs.searxng.org/admin/settings/settings_engines.html). | Install chosen engine extensions; none are installed initially. [Overview](https://degoog-org.github.io/docs/). |
| Favor small sites | [Hostnames plugin](https://docs.searxng.org/dev/plugins/hostnames.html) supports `high_priority`, `low_priority`, `remove`, and `replace`; engine weights can favor a small-web source. | [Domain scoring](https://degoog-org.github.io/docs/server-settings.html) adds positive or negative points after aggregation. Blocking and replacement are also supported. |
| Remember useful discoveries | Normal metasearch has no equivalent built-in history index identified in the reviewed docs. | Optional [indexer](https://degoog-org.github.io/docs/indexer.html) stores returned results locally; allow/block lists, age and size caps, export, and import are documented. It records queries/results, so enable only with a deliberate retention policy. |
| Ease of tuning | YAML config and plugins; broad [engine library](https://docs.searxng.org/dev/engines/index.html). | Settings UI and result-row actions; extensions are code installed from repositories, so review and pin what is installed. [Overview](https://degoog-org.github.io/docs/); [Using search](https://degoog-org.github.io/docs/using-search.html). |

For the Degoog trial, compare the same 20–30 personal queries across Wiby, Marginalia, Mwmbl, and DuckDuckGo. Add domain scores only after observing recurring unwanted or favored hosts. This is a proposed experiment, not a measured relevance claim.

## Operational caveats

The Degoog module is enabled for Rinoa. Its Compose service listens on Rinoa's
loopback port 4444 and shares the `proxy` Docker network with `cloudflare-tunnel`.
Pi-hole already resolves `search.local.solivan.dev` to Rinoa. Traefik accepts
LAN clients for that hostname. The settings password is generated on Rinoa in
`/var/lib/docker-containers/degoog/settings-password`; the persistent index and
settings live in `/var/lib/docker-containers/degoog/data`.

Degoog starts with no engines. On 2026-10-14, the official DuckDuckGo
extension and the 4get compatibility engines Wiby, Marginalia, and Mwmbl
were installed. A live query returned results. Install future extensions
only from reviewed repositories.
The public hostname has no DNS record yet. The Cloudflare Tunnel route must point `search.solivan.dev` directly to
`http://degoog:4444`. Add a Cloudflare Access policy for the owner's email
before publishing that route. The public hostname must not be routed through
Traefik, which has separate public entrypoints.

## Rinoa rollout

The current configuration is staged at `/home/danny/degoog-dotfiles-staging`
on Rinoa. Run the full host activation there:

```sh
sudo nixos-rebuild switch --flake 'path:/home/danny/degoog-dotfiles-staging#rinoa'
```

Then verify `http://127.0.0.1:4444/healthz` on Rinoa and
`https://search.local.solivan.dev/` from the LAN. In Cloudflare, create a
self-hosted Access application for `search.solivan.dev` with an Allow policy
for the owner's exact email address and one-time PIN authentication. Only after
that policy is active, add a public hostname to the existing tunnel with
service URL `http://degoog:4444`. The tunnel connector and Degoog share the
Docker `proxy` network. Add a Cloudflare rate limiting rule if the account plan
allows a rule scoped to this hostname. Confirm an unauthenticated request gets
the Access login page, then sign in and make a search. [Access application
setup](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/).

- Public discoverability is not an access control. Put the Cloudflare Tunnel hostname behind Cloudflare Access for the intended identity or group, then apply an edge rate limit as a second guard. Restrict the origin so only the local tunnel connector can reach it. (Cloudflare-specific configuration is outside this comparison.)
- [SearXNG's limiter](https://docs.searxng.org/admin/searx.limiter.html) requires Valkey and `server.limiter: true`; its IP behavior depends on trusted proxy and forwarding headers being correct. Upstream engines may CAPTCHA or block a server IP when traffic grows.
- [Degoog's rate limits](https://degoog-org.github.io/docs/server-settings.html) cover search and autocomplete separately; defaults are 15 searches per 20 seconds and 150 per 10 minutes per IP, plus 60 autocomplete requests per 20 seconds and 120 per minute per IP. Check proxy IP handling before relying on per-client limits. Its settings password is required before internet exposure because an open settings page can install code-running extensions. [README](https://github.com/degoog-org/degoog).
- Neither project's app limiter should be the only defense for an internet hostname. Identity gating at the edge prevents unauthenticated requests from reaching the tunnel and upstream search engines; app rate limiting remains useful for an authenticated session or misconfiguration.
