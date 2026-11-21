# Ventura magenta-window investigation

The supplied screenshots show ChatGPT with a solid magenta band or window region,
while the desktop, Dock and Henge controls remain visible. The guest is reported
as Ventura and the build is believed to be `80a6ed81b0d8`. The exact build/version
and the cause still require the affected session's `henge.log`.

The renderer previously returned silently when a draw or compute dispatch had
no valid pipeline. Such work did not appear in its `failed` counter. A guest
magenta clear followed by a skipped draw can therefore leave a magenta target
with no Metal command-buffer error. A native Metal regression reproduces this
sequence and checks that a subsequent valid pipeline renders green correctly.
This is a confirmed failure mechanism, not a diagnosis of the screenshots.

The follow-up build adds metadata-only `pvg-replay` events:

- `guest-magenta-clear`: the decoded guest pass requested a magenta clear.
- `draw-without-pipeline`: a requested render draw could not be submitted.
- `dispatch-without-pipeline`: a requested compute dispatch could not be submitted.

Events contain task/pipeline/attachment IDs, target size/format and legacy-driver
status. They are deduplicated and capped at 64 per VM replay. Periodic tallies
count every skipped draw/dispatch even after that cap. Pipeline construction
errors now include task and pipeline references for correlation. Ambiguous or
failed library function lookup reports counts/types, without shader contents.
No screenshots, pixels, buffer contents or account data are added to the log.

No rendering behavior, color conversion, resolution or redraw policy changes in
this follow-up. In particular, magenta is not replaced, suppressed or covered.
The new native regression explicitly checks the original magenta pixels as well
as successful rendering.

To collect evidence, launch the affected app with this build, reproduce once,
then use Henge Settings → Log → Share henge.log. Full GPU tracing is not needed;
its existing buffer/shader dumps are broader than these metadata diagnostics.

Interpretation:

- A magenta-clear event correlated with missing-pipeline events identifies a
  failed guest draw path; the matching pipeline error can explain rejection.
- Missing compute dispatches can leave textures incomplete even if their final
  composition pass has a valid render pipeline.
- If neither appears, investigate source surface content/format, guest command
  layout and synchronization with the affected session's mapping/GPU errors.
  The screenshots alone cannot distinguish those possibilities.

## Recovery of failed cached resources

The replay cached a nil result for function and serialized-pipeline objects as
though it were a successful immutable resource. Later uses with the same guest
entry returned that nil indefinitely. The replay now retries failed resources
with exponential delay (50 ms to a 4-second maximum), while keeping successful
objects cached. A changed guest entry bypasses the old failure's cooldown, and
recursive access to an object still being built returns unresolved rather than
recursing without bound. Recovery is logged as `resource-recovered` with task/ref/type and failure count,
capped at 32 messages per replay. Magenta clears and skipped draws remain visible in
metadata; no color or pixel is suppressed.

The native replay regression substitutes availability of a shader, not the cache:
it first fails a pipeline through the real object table/cache, then supplies a
real Metal function and checks that the same refs build a real pipeline after
expiry. It also checks no immediate retry storm and retained successful objects.
The portable retry-delay test passes under ASan/UBSan. Native Metal validation
and final packaging of this follow-up are pending while GitHub Actions is disabled.
This repairs a confirmed failure-cache bug; whether it explains the reported Codex
rectangles still needs the affected session's ordinary `henge.log`.
