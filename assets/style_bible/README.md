# UNSEEN — Style Bible (the art anchor everything is generated against)

This folder holds the **2–3 canonical reference sprites** that define Unseen's look
(`PHASE_8_MONETIZATION.md` §7.1). They are the immovable anchor: **every** PixelLab
generation — base civilian, cosmetics, clones — passes one of these as the style
reference. **Never delete or "improve" them mid-season.** Drift starts the moment art
is generated cold from a text prompt with no reference.

If you change nothing else here, obey this: **one base civilian, generated once, hand-
finished, then reused as the reference for everything.**

## LOCKED ART DIRECTION (Aaron's call — see `ART_PIPELINE.md` §0/§2)
- **Full pixel art, map included.** The whole game is pixel — one coherent identity.
- **Clean / refined, NOT chunky/retro.** Muted palette, soft ambient shadows, orderly tiling,
  selective edge-smoothing in the hand-finish — an "AC-style clean urban" feel.
- **48×48 base, top-down, 4-direction, pivot at the feet.** (Aaron's call — richer clean-urban detail;
  sheets are 4×4 = 192×192. The rig's `FRAME_PX` stays 32 until the first 48px sheets replace the
  placeholders, then flips to 48 — don't flip it before the new art exists or placeholders mis-slice.)
- **Starting master palette — muted urban** (refine from the first hand-finished base civilian + tile,
  then enforce it in `tools/ingest_sprite.py`):
  - stone / paving: `#cbc4b2 #c3bca9 #aaa28d #8f8a7e`
  - clay roof / wood: `#b08a5e #a9845a #8f6f48 #6e5436` · highlight `#cda978`
  - slate / shadow: `#6f6678 #4a525a` · water: `#3a7fa8 #4f93bc`
  - skin / hair / outline: `#d9a878 #3a2c22 #33303a` · void `#191a1d`

---

## 1. The art-direction decision (read before generating anything)

The monetization model (`PHASE_8_MONETIZATION.md` §2A) changes the art target:

- **There is ONE base civilian body.** Cosmetics (outfit / head / weapon) ride on it.
  The look that differentiates a character is the *cosmetic*, not a separate "class
  sprite." (The current 5 sheets — villager / merchant / guard / mage / townswoman —
  are **placeholders**; treat `villager_sheet.png` as the interim anchor until the real
  base civilian below is generated.)
- **Every NPC is a clone of a player's equipped look** (the §2A crowd, already built as
  the per-viewer appearance system — `clones_per_player` ≙ the code's
  `look_copies_per_player`). So the **same 48×48 sprite is used for the player avatar
  AND its clones** — which is what makes render parity automatic for static art (§2A.1).
- **Crowd-safe silhouette rule (the §0 veto).** Every in-match (CROWD_SAFE) cosmetic must
  still read as "a plausible townsperson." If a skin breaks the civilian silhouette or
  out-reads the others, it's pay-to-lose/win — it doesn't ship as an in-match skin (push
  the glamour to a reveal-moment or store/preview asset instead). The code tag for this is
  `CosmeticItem.Bucket` / `is_crowd_safe()`.

---

## 2. The exact rig format to hit (from `scripts/character_visual.gd`)

New art MUST match the rig or it won't drop in:

- **Frame size:** 48×48 px. Sheet = a **4×4 grid** (192×192): **rows = facing**
  (0 down, 1 up, 2 left, 3 right), **columns = the 4 walk-cycle frames**.
- **Pivot / origin:** centred, feet-aligned. The rig composites every layer against one
  **locked centre origin** — author to the same 48px-frame centred convention so swapping
  a hat can't shift the character a pixel.
- **Filtering:** authored as crisp pixel art (the rig uses NEAREST). No anti-alias fuzz.
- **Background:** transparent.
- **Layers:** the rig stacks `body` (z0) / `outfit` (z1) / `head` (z2) / `weapon` (z3),
  recolourable via `modulate` (author light/greyscale where you want runtime tinting;
  a cosmetic's `default_palette = NO_RECOLOR` means "draw as authored").

---

## 3. The base-civilian recipe (generate this first, once)

Goal: `civilian_base_s.png` — a neutral base townsperson, **south/front-facing**, final
**48×48**, hand-finished to the quality bar everything else must match.

PixelLab (`PHASE_8_MONETIZATION.md` §6–§7):
1. **Concept** with `PixFlux` (~1 credit) to rough the silhouette: *"top-down 2D pixel art
   townsperson, plain medieval/ancient city civilian, neutral tunic, front-facing, 32x32,
   readable silhouette, no logos."* Iterate cheap until the silhouette reads.
2. **Lock the look** with `BitForge` (style-reference, ~40 credits) using your best concept
   as the reference, at 48×48. Re-roll 2–4× and keep the best **south** frame.
3. **Hand-finish** that one frame in Aseprite to the §7.7 checklist — this is your anchor.
   Save it here as `civilian_base_s.png`. Optionally add `_e` (east) / `_n` (north) anchors.
4. **Set the finished south frame as the reference image**, then `rotate` to the 4-direction
   set (confirm the rotation tool's facing order matches §2's row order **before** batch-running).
5. `animate_character` the **idle + 4-frame walk** from the reference so frames hold shape.
6. Export → repack to the 4×4 / 48×48 sheet (`MapBuilder`/Pillow packer) → drop into the rig.

**Then** every cosmetic is made by starting from this saved base character and using
`inpaint` / outfit-transfer to add clothing (§7.2) — never cold.

---

## 4. Palette discipline

- Pick a small, fixed master palette and keep all cosmetics inside it (the §7.7 "no stray
  colours / mixels" check). A tight palette is most of what makes a crowd read as one place.
- Warm stone / earth tones suit the "Rome / old-city" maps (see `maps/rome.tscn`).
- Keep cosmetics **readability-equivalent** (§2A.1): no skin so busy it masks the behavioural
  tell, or it becomes mild pay-to-win.

---

## 5. File / naming conventions (`PHASE_8_MONETIZATION.md` §7.9)

- Style bible: `assets/style_bible/civilian_base_s.png` (and `_e`, `_n` if used).
- Cosmetic source frames: `assets/cosmetics/<season>/<cosmetic_id>/<dir>_<anim>_<frame>.png`
- Store / preview art: `assets/cosmetics/<season>/<cosmetic_id>/preview.png` (any res — it's
  marketing art, decoupled from the 48×48 in-game sprite per §7.6).
- **`cosmetic_id` must match the `id` in the `CosmeticRegistry`** so the loader finds the art.

---

## 6. Reminders that bite later if skipped

- **Two-asset rule (§7.6):** the 48×48 in-game sprite ≠ the store glamour render. Make both.
- **AI / Steam disclosure (§9):** PixelLab output is AI-generated — disclose it on Steam
  submission and keep a note of which assets are AI-assisted. Keep cosmetics original (no
  real brands / recognizable IP). Confirm PixelLab's commercial license at ship time.
- **Don't train other models on PixelLab output** — their license forbids it.
