# UNSEEN — Phase 8: Monetization & Cosmetics

Status: planned. Open when Phase 7 is stable and the core hunt is fun-tested.
Owner: Aaron. Art polish: brother (Aseprite). Generation: PixelLab + Claude/Codex.

This doc has two halves:
1. **What to do** — the monetization decisions and the order to build them in.
2. **The PixelLab protocol** — how to actually generate cosmetics the right way.

> Implementation status (this repo): the cosmetic data model, equip, ownership gate
> (Phase 8) and the player-derived clone crowd of §2A (built as the Phase 9 per-viewer
> appearance system — `clones_per_player` ≙ `look_copies_per_player`) already exist.
> Still to build per §4: battle-pass backend, store/entitlements, Steam MTX. Art pipeline
> anchor lives in `assets/style_bible/` — see its README before generating anything.

---

## 0. The one rule that governs everything

Unseen is a blend-into-the-crowd game. The entire skill loop depends on a hidden
player being **visually indistinguishable from AI civilians**. Monetization must
never break that. Two failure modes, both fatal:

- **Pay-to-lose:** a purchased skin makes your civilian stand out → hunters pick
  you out for free → nobody buys it, or worse, buyers get punished.
- **Pay-to-win:** a purchased skin helps you blend *better* than non-payers →
  the hunt becomes about wallet, not skill.

So the design constraint is: **in-match civilian appearance must stay
mechanically neutral.** Cosmetics that touch the in-world civilian silhouette are
only allowed if they are *camouflage-neutral* (see §2). Everything else gets
monetized away from the civilian sprite — finishers, the hunt UI, profile flair,
store art. Treat this section as a veto: if a cosmetic idea can't pass it, it
doesn't ship, no matter how good it looks.

---

## 1. Model (already decided — restated so it's in one place)

- Free-to-play.
- Cosmetic-only monetization. No gameplay advantages, ever.
- Battle pass as the primary cosmetic delivery vehicle, plus a direct store.
- No loot boxes / randomized paid rewards (regulatory and trust risk; avoid).

---

## 2. Cosmetic taxonomy — what's safe to sell

Sort every cosmetic into one of three buckets before building it.

### A. Crowd-safe — the player-derived crowd (CHOSEN MECHANISM)
The NPC crowd is not a separate civilian pool. **Every NPC is a clone of a
player's equipped look.** Each client reskins the shared crowd to represent the
*other* players in the lobby: in a 4-player lobby, each player sees the crowd as
three groups of clones — one per opponent. The real opponents are mixed in among
their own clones.

Why this is neutral by construction:
- You are always hidden among NPCs wearing **your exact outfit**, so your
  cosmetic can never make you stand out — the haystack is needles that look like
  you. Not pay-to-lose.
- Every player gets the same "blend into copies of yourself" treatment regardless
  of how fancy the skin is. A fancier skin just means a fancier clone-crowd.
  Not pay-to-win.
- It's also the best possible cosmetic *showcase*: from every opponent's screen,
  whole crowds wear your outfit. Maximum visibility = strong purchase motivation,
  with zero competitive impact.

This replaces the earlier "shared wardrobe / per-match" options — it's a cleaner
solution to §0 and it's what Phase 8 builds around.

Because outfit is now neutralized, **all** hider-vs-hunter skill moves to
**behavior** (intentful movement toward objectives vs NPC wander + compass).
That's intended: cosmetics become pure flair with no gameplay weight.

### A.1 Implementation rules this mechanism demands (non-negotiable)
Violating any of these quietly reintroduces pay-to-lose or pay-to-win.

- **Render parity.** A cosmetic must render pixel- and animation-identically on
  the real player and on their clones. Any divergence is a tell. For a static
  sprite this is automatic (the clone *is* the same asset). The risk is
  **animated / particle layers** — if clones can't reproduce a persistent effect
  with identical timing and phase, that effect does **not** ship as an in-match
  skin. Move it to a reveal-moment cosmetic (§2B) instead.
- **Behavior parity of clones.** Clones wander using the same animation system as
  the player avatar, so the only true tell is pathing/intent — never a rendering
  difference.
- **Tell channel must be outfit-proof.** The real-vs-clone tell lives in gross
  movement and pathing, not in fine sprite detail a busy cosmetic could mask.
  Otherwise a visually noisy skin becomes mild pay-to-win. Keep all cosmetics
  readability-equivalent as an art guideline.
- **Clone count is the blend-difficulty knob.** Per target, the haystack is only
  that target's clones (you scrutinize one outfit-group, not the whole crowd).
  So `clones_per_player` directly sets blend strength, and
  `total_crowd ≈ (lobby_size − 1) × clones_per_player`. Tune it for the blend you
  want, then check it against the crowd-size budget your Phase 6 netcode can
  carry. Bigger lobbies splinter the crowd into more, smaller groups — protect
  the per-target clone count or the blend collapses.
- **Per-viewer reskin, shared entities.** Positions and behavior are one synced
  crowd; only the *skin* differs per viewer, keyed to opponent cosmetic IDs.
  Appearance is a cosmetic-ID lookup, not per-NPC sprite data — so it stays
  netcode-cheap (one cosmetic ID per player at match start, nothing per-NPC).
- **Hunter info design interacts with this.** If a player knows their target's
  outfit, finding the right *group* is trivial and all skill is picking the real
  one from identical clones. Decide deliberately how much the hunter knows
  (compass-only is a good default, so they still must locate the group). See §8.

### B. Reveal-moment cosmetics (safe — only show when stealth is already broken)
These are the money-makers because they're flashy *without* affecting the blend:
- Assassination / finisher animations (only play during the kill).
- Death / desync effects (only play when you're already caught).
- Weapon and tool skins (only visible mid-action, per asymmetric class).
- Target-ping / exposure-arrow visual themes (your own HUD, invisible to others).

### C. Out-of-match cosmetics (always safe)
- Lobby avatars, profile banners, name colors, titles, emotes in lobby.
- Battle pass card art, season badges.

**Rule of thumb:** the more a cosmetic is visible *during* the blend phase to
*other* players, the more constrained it is. Push the glamour into buckets B and C.

---

## 3. Battle pass structure (decide these numbers, then build)

Fill these in before producing art — they set how many assets you need.

- [ ] Season length: ______ weeks (start with 6–8; shorter = more art pressure).
- [ ] Tiers per season: ______ (30–50 typical).
- [ ] Free track reward count: ______ (keep it generous; free players are your crowd).
- [ ] Premium track reward count: ______.
- [ ] Price point: ______ (note local currency; Steam regional pricing later).
- [ ] Premium-plus / tier-skip option? yes / no.

**Asset math:** (premium rewards + free rewards) × (frames per cosmetic) =
your per-season generation load. Plug into the credit worksheet in §7.8 before
committing to a cadence you can't art-sustain solo.

---

## 4. Build order for Phase 8

Do these in sequence. Don't start art production before the framework exists,
or you'll generate assets the system can't equip.

1. **Cosmetic data model.** A data-driven `COSMETICS` array (mirror your
   `DISTRICTS` pattern): id, bucket (A/B/C), slot, rarity, season, equip rules.
2. **Equip + slot system.** How a cosmetic attaches to a character/finisher/HUD.
3. **Player-derived crowd system.** Implement the clone mechanism from §2A:
   per-viewer reskin of the shared crowd keyed to opponent cosmetic IDs, with
   render + behavior parity (§2A.1). Load-bearing — build and prove it first, and
   tune `clones_per_player` here, before any cosmetic art exists.
4. **Battle pass backend.** XP/track progression, free vs premium gating,
   claim flow. Keep server-authoritative.
5. **Store + ownership.** Entitlements, what the player owns, restore on login.
6. **THEN** start producing cosmetic art with the PixelLab protocol below.
7. **Preview/store art pipeline.** Higher-res glamour renders (see §7.6).
8. **Steam integration.** Microtransactions via Steam, AI content disclosure (§9).

Definition of done: a player can earn a free-track cosmetic and buy a
premium-track cosmetic, equip both, and the crowd-safe rule provably holds in a
live match (verify by trying to spot a skinned player in a crowd — you shouldn't
be able to).

---

## 5. Production pipeline (one line)

PixelLab (generate variant) → Aseprite (hand-finish) → Python/Pillow (repack to
32×32 sheet) → Godot (`MapBuilder` / cosmetic loader) → in-engine test.

---

## 6. PixelLab — account & model facts

Verify current numbers against your live account; these are working assumptions.

- **Tier:** Tier 1 "Pixel Apprentice" (~$12/mo, ~2,000 credits/mo, up to 320×320).
  Loyalty discount drops it toward ~$9/mo over consecutive months.
- **Do not upgrade for features.** Tier 2/3 mainly buy bigger canvas (400px),
  priority queue, concurrency, and team seats — none of which a solo 32×32 dev
  needs. Only move up if you genuinely exhaust monthly credits, and prefer a
  **pay-per-credit top-up** for occasional overflow instead of a tier jump.
- **Models & cost:**
  - `PixFlux` — basic text-to-pixel. ~1 credit/request. Use for rough concepts.
  - `BitForge` — style-reference generation. ~40 credits/request. This is the
    one you'll lean on for consistent cosmetics. Budget accordingly.
- **Small-sprite efficiency:** at 32×32 you get ~16 animation frames per request
  (vs ~4 at 128×128). Your sprite size works in your favor.
- **Licensing:** commercial use included on paid plans. **Do not** train other
  models on PixelLab outputs (their license forbids it).

---

## 7. PixelLab generation protocol

This is the operational core. Follow it in order for every cosmetic.

### 7.1 Build the style bible first (do this once)
Lock **2–3 canonical reference sprites** that define Unseen's look: a base
civilian, front-facing, at final 32×32, hand-finished to the quality bar you
want everything to match.

- Store them in `assets/style_bible/` in the repo. Never delete or "improve"
  them mid-season — they are the anchor.
- Every cosmetic generation **must** pass one of these as the style reference.
- Rule: **never generate a cosmetic cold from a text prompt only.** Cold
  generation is where style drift starts.

### 7.2 Per-cosmetic workflow (the loop)
For each new outfit/skin:

1. Start from your **base character** (a saved PixelLab character, so it has a
   `character_id` and consistent identity), not a fresh generation.
2. Use **inpainting / outfit transfer** to add the new clothing/accessory. This
   edits the existing sprite while matching style — it is literally the "make a
   cosmetic" tool. Pass a style-bible reference.
3. Review the south-facing result. If it's off-style, re-roll (expect 2–4
   attempts; this iteration is your main credit sink). Keep the best frame.
4. **Set that approved frame as the reference image** for everything downstream,
   so rotation and animation stay consistent with it.
5. **Rotate** to your direction set (4 or 8). Verify the rotation tool's output
   direction order and facing match your Godot convention *before* batch-running
   — re-mapping frames by hand later is the time sink to avoid.
6. **Animate** the cycles you need (idle, walk; run/attack if the class needs
   it). Generate from the reference so frames hold shape.
7. Export frames → §7.7 hand-finish → repack → Godot.

### 7.3 Consistency discipline (why drift happens, how to stop it)
- Drift is universal to AI generation, not a PixelLab flaw. Later animation
  frames are the usual offenders (a belt shifts a pixel, a shadow flickers).
- Counter it by: (a) always passing a reference, (b) generating in small batches,
  (c) starting animations at 2 frames to lock the look before extending,
  (d) the hand-finish pass in §7.7.

### 7.4 Rotation notes (top-down)
- 4-direction is the minimum for a top-down blend game; 8 if your movement and
  read-resolution justify it. More directions = more frames = more credits and
  more hand-finish. Start at 4, only go to 8 if facing-reads feel coarse.
- Confirm facing maps to your input vectors so a character faces where it walks.

### 7.5 Animation notes (32×32)
- Walk + idle are the must-haves for civilians and cosmetics. Reveal-moment
  cosmetics (§2B) may add a finisher animation — those are worth extra polish
  since they're the paid glamour.
- Frames export as PNG → route through your existing Pillow sheet packer. Keep
  the 32×32 frame grid convention consistent so `MapBuilder` ingestion doesn't
  change.

### 7.6 The two-asset rule (important for a paid battle pass)
At 32×32 an in-world cosmetic is mostly silhouette, palette, and a few signature
pixels — there's a hard detail ceiling. So **decouple the in-game sprite from the
store art**:

- **In-match asset:** the 32×32 sprite, crowd-safe, neutral. **This same asset is
  the NPC clone skin** — there is one sprite per cosmetic, used for both the
  player avatar and their clones, which is what makes static render parity (§2A.1)
  automatic. Any animated/particle layer added on top is the part that needs the
  parity check.
- **Store / battle-pass preview asset:** a separate, higher-res glamour render at
  any angle you like (3/4 hero shot). This is what actually sells the skin. It
  does **not** need to match the in-game resolution or even the exact in-match
  appearance — it's marketing art.

Never let the 32×32 limitation gate how good the *store* looks. Generate previews
at a larger canvas (or a different tool if needed) purely for the menu.

### 7.7 Hand-finish checklist (per cosmetic, before it ships)
AI gets ~80%; this pass is where paid quality comes from. In Aseprite:

- [ ] Silhouette still reads as "a civilian" (crowd-safe check).
- [ ] Palette matches the style bible (no stray colors / mixels).
- [ ] No drift across rotation frames (same proportions every direction).
- [ ] No drift across animation frames (belt/shadow/accessory stable).
- [ ] Clean 1px outlines, no anti-alias fuzz at 32×32.
- [ ] Transparent background, correct pivot at the feet.
- [ ] Looks right in-engine at actual game zoom, in a crowd, not just zoomed in.

### 7.8 Credit budgeting worksheet
Measure real burn on your **first 2–3 cosmetics**, then project. Per cosmetic:

```
base outfit (inpaint/transfer)   ___ requests  × ___ credits = ___
iteration re-rolls               ___ requests  × ___ credits = ___
rotation (4 or 8 dir)            ___ requests  × ___ credits = ___
animation (idle/walk/…)          ___ requests  × ___ credits = ___
                                              per-cosmetic total = ___

per-cosmetic total × cosmetics per season ÷ season months
                                          = credits needed / month
```

If monthly need < ~2,000 → Tier 1 holds. If you spike in a production crunch,
buy a credit pack that month rather than upgrading permanently.

### 7.9 File / naming conventions
- Style bible: `assets/style_bible/civilian_base_s.png` etc.
- Cosmetic source frames: `assets/cosmetics/<season>/<cosmetic_id>/<dir>_<anim>_<frame>.png`
- Store art: `assets/cosmetics/<season>/<cosmetic_id>/preview.png`
- Keep `cosmetic_id` identical to the id in the `COSMETICS` data array.

### 7.10 MCP setup (optional — nice-to-have, not required)
If you want Claude/Codex to drive generation from VS Code:

```jsonc
{
  "mcpServers": {
    "pixellab": {
      "url": "https://api.pixellab.ai/mcp",
      "transport": "http",
      "headers": { "Authorization": "Bearer YOUR_API_TOKEN" }
    }
  }
}
```

Tools exposed include `generate_image_pixflux`, `generate_image_bitforge`
(style reference), `create_character` (4/8 dir), `animate_character`,
`rotate`, `inpaint`, `create_tileset`. The same protocol above still applies —
the MCP just lets the agent make the calls. Always pin the style-bible reference
in the call; the agent will drift faster than you will if you don't.

---

## 8. Things to stress-test before building (don't skip)

- **Crowd-safe proof:** can a hunter pick the real player out of their clone
  group? If yes, the cosmetic (or the render parity) is broken. Test specifically
  with your busiest/most-animated cosmetic, not a plain one.
- **Render parity on animated cosmetics:** put a particle/animated skin on a
  player and surround them with clones — does the real one catch the eye because
  its effect is out of phase? If so, that skin moves to reveal-moment (§2B).
- **`clones_per_player` tuning:** with the per-target haystack being one outfit
  group, is the blend tense at your target clone count? Sweep the value and find
  the floor where hiding still feels fair. Re-check at your max lobby size, where
  the crowd splinters into more, smaller groups.
- **Busy-outfit masking:** does a visually noisy skin make the behavioral tell
  harder to read than a clean one? If yes, that's mild pay-to-win — push the tell
  further into pathing/intent and away from fine sprite detail.
- **Crowd coherence:** with 3+ different player outfits cloned across the crowd,
  does it still read as a plausible townsfolk crowd, or as a costume contest?
  Constrain cosmetic silhouettes if the crowd stops reading as civilians.
- **Hunter info:** how much does a player know about their target's look? Tune so
  identifying the *group* isn't free (compass-only is a good starting point) —
  otherwise all skill collapses to one read.
- **Cosmetic showcase feel:** seeing whole crowds wear an opponent's skin is the
  monetization hook — confirm it actually reads as "cool, I want that" in
  playtests, since that perception is doing the selling.
- **Finisher cosmetics vs readability:** flashy kill animations can't leak
  information that unbalances the hunt (e.g. revealing positions).
- **Free-track generosity:** free players are the crowd that makes the game work.
  Starving the free track hurts the core loop, not just goodwill.

---

## 9. Legal / Steam disclosure

- Steam's content survey now has an **AI disclosure** section. Cosmetics made
  with PixelLab are **pre-generated** AI content — disclose them as such when you
  submit. Keep a short internal note of which assets are AI-assisted.
- You're responsible that outputs aren't infringing; keep cosmetics original
  (no real brands, no recognizable IP).
- Confirm PixelLab's commercial license terms still cover your use at ship time.

---

## 10. Definition of done — Phase 8

- [ ] Crowd-safe rule implemented and proven in a live match.
- [ ] Cosmetic data model + equip + store + battle pass functional end to end.
- [ ] Style bible locked; first season's cosmetics produced via the §7 protocol.
- [ ] In-match and store assets both exist for every shipped cosmetic.
- [ ] Steam microtransactions + AI disclosure handled.
- [ ] A free player and a paying player both have a satisfying cosmetic path.
