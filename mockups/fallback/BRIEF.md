# Sidestep landing page · section brief

You are building ONE section part for a landing-page shuffler. Read this whole file, then read
`parts/_head.html` (tokens, the exact app component, the shuffler chrome) before writing anything.

## The product
**Sidestep** is a native macOS menu-bar app (Swift/SwiftUI, no Electron). It watches every Claude
account you're signed into, shows three rows per account as segmented ladders: session (5H), weekly (7D, all models),
and FABLE (the Fable model has its own separate weekly bucket, and you want it at a glance), polls Anthropic's `GET api.anthropic.com/api/oauth/usage` every 60 s (picker: 30 S to
15 MIN), and switches which account Claude Code uses by dragging a metal knob down a gear-shifter
slot (one gate per account). A switch = 3 writes: snapshot the current Keychain login to a proxy
file (`~/.cli-proxy-api/claude-<email>.json`), write the chosen tokens into the `Claude
Code-credentials` Keychain item, update `oauthAccount` in `~/.claude.json` (backup
`.sidestep-bak`). Running Claude Code sessions pick it up on their next turn because Claude Code
shells out to `security find-generic-password` with a 30 s cache. No restart. The app also draws a
±7 day reset Gantt ("RESET WINDOWS · ±7 DAYS"): NOW line in the middle, each account's 7D window
filled to % used, an end tick with "30% TUE 7P", a thin model bar, a ◆ for the 5H reset. Re-auth
accounts show two dashed rows, a ▲ warn note like "TOKEN BELONGS TO JOHN@M…" and a SIGN IN → button;
their shifter gate is hatched and the knob refuses (shakes back). "+ ADD ACCOUNT" runs the real PKCE
OAuth flow (browser → localhost:54545, or paste `code#state`). Refresh-token rotation is handled:
the new refresh token is written everywhere that account is held. No telemetry, no server.

**The menu bar title** is the active account's `session% · weekly%` (e.g. `17% · 4%`), dot orange
under 50%, amber 50–79%, red 80%+.

## Voice
Quippy, personal, dry, a little cocky. Like a friend who built this because they were mad.
Short sentences. Specific over clever. **Never use an em dash** (no "—" in prose; the "—" glyph is
allowed ONLY inside the app drawing where the real app shows a dash for no data). Contractions
fine. Swearing: no. Examples of the register:
- "Claude said you've had enough. You haven't."
- "Rate limits are a you problem now."
- "Not a Chromium window in a trench coat."
- "So you close the laptop and go outside like some kind of animal."
- "QUIT quits. ⌘Q also quits. Revolutionary."
People named in the demo data: Alexa, Derek, John, Nithin (all real accounts, keep them).

## The rules
1. **Three FULL versions.** Not three headlines. Three genuinely different layouts, compositions,
   and ideas for the same section, each with its own name ("The Tape", "The Two Numbers"…). A
   reader flipping A→B→C should feel like three different designers pitched the section. Vary the
   grid, the scale, the lead visual, what's interactive.
2. **Draw the real app, never an impression of it.** Every panel, row, ladder, gate, knob, tape,
   footer or menu bar on the page comes from `renderApp()` / the `.app` CSS in `_head.html` or the
   `.mb` menu-bar strip. Do not invent UI the app doesn't have (no ACTIVE pills, no icons, no
   fake settings). You MAY blow parts up (a single account row at 2×, the tape full-width, the
   shifter alone) by rendering with options (`header:false`, `accounts:[ACCTS[2]]`, `shifter:false`,
   `tape:true`, `fluid:true`) and scaling with CSS `zoom` or `transform:scale()` on a wrapper.
   Read the option list at the top of the `<script>` in `_head.html`.
3. **Scope everything.** Your section id is `sNN`. Every class you create is prefixed `sNNa-`,
   `sNNb-`, `sNNc-` (one per version). Put your `<style>` at the top of your part, your `<script>`
   at the bottom (wrapped in an IIFE). Never restyle `.app`, `.mb`, `.btn`, `.w` or anything global.
   Ids inside your part must be prefixed `sNN`.
4. **Section skeleton** (copy exactly, fill in):
   ```html
   <style>/* sNN */ …</style>
   <section class="sblk" id="sNN" data-sec="sNN" data-count="3">
     <header class="sbar"><div class="sbar-w">
       <div class="sbar-id"><span class="sbar-n">NN</span><span class="sbar-t">Section Title</span><span class="sbar-k">one-line purpose</span></div>
       <div class="sbar-nav"><span class="sbar-lbl" data-lbl>Name of A</span>
         <button class="sw-arw" data-step="-1" aria-label="Previous version">‹</button>
         <div class="sw-dots"><button class="sw-dot on" data-go="0" title="Name of A">A</button><button class="sw-dot" data-go="1" title="Name of B">B</button><button class="sw-dot" data-go="2" title="Name of C">C</button></div>
         <button class="sw-arw" data-step="1" aria-label="Next version">›</button></div>
     </div></header>
     <div class="vars">
       <div class="var on" data-var="0" data-label="Name of A"> … full layout A … </div>
       <div class="var" data-var="1" data-label="Name of B"> … full layout B … </div>
       <div class="var" data-var="2" data-label="Name of C"> … full layout C … </div>
     </div>
   </section>
   <script>(function(){ … renderApp calls, any per-version interactivity … })();</script>
   ```
   Content width: wrap copy in `<div class="w">`. Full-bleed versions may skip `.w` for the
   background and use it inside. Section vertical padding: ~96–120px desktop.
5. **Motion:** use `.rv` (+ `.rv.d1/.d2/.d3`) on elements for scroll reveal; the shuffler adds
   `.in`. Version-specific load animations: set `varEl._onShow = fn` on your `.var` element and the
   shuffler calls it whenever that version becomes visible (and on Replay). Respect
   `reduceMotion` (a global boolean). Keep it purposeful; one orchestrated moment beats confetti.
6. **Every version must be responsive** (single column under 900px), theme is single dark
   (paint colors explicitly from the tokens), no external assets, no images, no CDN. Google Fonts
   are already loaded in the head: `var(--cond)` display, `var(--sans)` body, `var(--mono)` data.
7. **Test it.** Before you finish, run `node build.cjs` from `mockups/sidestep/` and then render
   with the headless script at
   `/private/tmp/claude-501/-Users-john-Developer-sidestep/6dadd696-981c-4873-a77d-8b3e96199d02/scratchpad/shot-section.mjs sNN`
   (usage: `node shot-section.mjs s03` → writes `s03-A.png`, `s03-B.png`, `s03-C.png` in that
   scratchpad dir and prints console errors). Look at all three PNGs. Fix overlaps, clipped text,
   broken gates, empty panels. Zero console errors.
8. Write ONLY `parts/sNN.html`. Do not touch `_head.html`, `_foot.html`, `build.cjs`, or other
   parts. Your final message: the three version names, one line each on what's different, and
   anything you couldn't make work.

## Demo data available (from `_head.html`)
`ACCTS` = [Alexa (locked, re-auth), Derek (0% / 0%, FABLE 0%, 7D resets 5D 4H), John (17% / 4%,
FABLE 7%, active by default), Nithin (0% / 3%, FABLE 6%)]. Use `override:{John:{s:97,w:71,m:88}}`
to show a hot account. Build your own `accounts:[…]` arrays when a version needs a different story
(e.g. two accounts both at 70% with different reset days).

## Correction (owner, 2026-08-24)
**Never mention Opus.** The three rows are exactly: `5H` (session), `7D` (weekly, all models), `FABLE`
(Fable's own weekly bucket, shown because it's separate usage you want at a glance). Call the third
row "the Fable row" or "the Fable bucket" in copy, never "model buckets" plural, never "Fable or Opus".
