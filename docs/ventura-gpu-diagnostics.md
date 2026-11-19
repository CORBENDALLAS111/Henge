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
