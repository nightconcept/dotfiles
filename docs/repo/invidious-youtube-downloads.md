# Invidious as a download path for Pinchflat

Investigated on 2026-10-29 using upstream documentation and source.

## What can work

Invidious provides a download form on video pages. It offers combined audio/video formats when available, separate video and audio streams, and captions. An instance can disable downloads. Current code sends downloads through Invidious companion when configured. Separate streams require merging for a normal Plex video file. [Download widget source](https://github.com/iv-org/invidious/blob/master/src/invidious/frontend/watch_page.cr)

The frontend still retrieves media from YouTube. The documented default sends video streams directly from Google to the viewer. The `Proxy videos` preference relays streams through the instance. [Invidious FAQ](https://docs.invidious.io/faq/)

Current watch-page code proxies progressive streams when `local` is enabled and always proxies DASH streams. Thus a working page does not prove that every download uses the instance as a relay. [Watch route source](https://github.com/iv-org/invidious/blob/master/src/invidious/routes/watch.cr)

Invidious companion uses YouTube.js to retrieve streams. It also serves other clients through HTTP APIs. Its DASH and `latest_version` endpoints support `local=true` for proxied media URLs. Public operators can restrict these endpoints; upstream asks clients to respect those restrictions. [Companion repository](https://github.com/iv-org/invidious-companion), [Companion HTTP API](https://github.com/iv-org/invidious-companion/wiki/How-to-communicate-with-Invidious-companion-with-any-client-(HTTP-API))

## Why replacing the hostname is insufficient

yt-dlp recognizes supported Invidious hosts with its YouTube extractor. That extractor takes the video ID and constructs a `www.youtube.com/watch` URL. Passing such an Invidious watch URL to yt-dlp therefore does not use its proxy. A downloader must use the actual proxied stream or manifest instead. This conclusion follows from the URL matcher and extraction code. [yt-dlp YouTube extractor](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_video.py)

## Limits on self-hosting

Invidious documents the same YouTube bot challenge seen by Pinchflat. Possible causes include client detection and blocked outbound IP addresses. It recommends current Invidious plus companion, then offers changes to outbound connectivity, with no guarantee of success. [YouTube error guide](https://docs.invidious.io/youtube-errors-explained/)

Inference: companion uses a different extraction stack, so the failed bgutil test does not prove companion will fail. However, hosting it behind the same outbound IP does not remove any restriction associated with that IP. The existing errors do not establish that an IP block is the cause.

## Public-instance checks

Checks from Terra on 2026-10-29 requested `/api/v1/videos/lei5bqds-xQ?local=true`:

| Instance | HTTP status |
| --- | --- |
| `inv.nadeko.net` | 403 |
| `invidious.nerdvpn.de` | 401 |
| `yt.chocolatemoo53.com` | 500 |
| `invidious.tiekoetter.com` | 403 |

None supplied stream URLs. Additional HTTP checks requested `/watch?v=lei5bqds-xQ&local=true` with a browser user agent:

| Instance | Watch-page result |
| --- | --- |
| `inv.nadeko.net` | HTTP 418; instance bot-check page |
| `invidious.nerdvpn.de` | Remote connection closed |
| `yt.chocolatemoo53.com` | HTTP 200; instance CAPTCHA challenge |
| `invidious.tiekoetter.com` | HTTP 200; Anubis bot-check page |

These checks found no confirmed playable media. Browser playback after completing an instance's challenge was not tested. Instance bot checks are separate from YouTube's bot challenge. No local Invidious or companion deployment was made during this research.

## Practical next step

First confirm a real Ben 10 video plays and downloads through an available instance. Use its download control or proxied manifest rather than feeding its watch URL into Pinchflat. A temporary companion test on Terra could assess the different extraction stack before adding a permanent service. A public instance may provide different outbound connectivity, but availability and operator restrictions remain constraints.

## Local trial

A temporary local trial on 2026-10-29 used `quay.io/invidious/invidious:latest`,
`quay.io/invidious/invidious-companion:latest`, and PostgreSQL 14. The frontend
reported version `2026.10.22-b852c4b` and returned HTTP 200 for its stats endpoint.
Only the frontend was published, on `127.0.0.1:13000`. No account cookies were used.

The selected episode was Ben 10 (2005), S01E01, “And Then There Were 10”
(`lei5bqds-xQ`). Its video API request returned HTTP 500: Companion was waiting
for a valid PO token. Companion generated tokens but repeatedly failed its
automatic validation, reporting no valid formats for its validation videos.
No episode media was downloaded or copied to Titan. This does not establish
whether the cause is client detection, an outbound IP restriction, or another
upstream incompatibility. The temporary services were stopped after the trial.
