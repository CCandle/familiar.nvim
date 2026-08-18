local function S(text, role)
  return { text = text, role = role }
end

local function R(...)
  return { ... }
end

local function F(...)
  return { rows = { ... } }
end

return {
  id = "mote",
  kind = "glyph",
  version = 1,
  width = 12,
  height = 3,
  palette = {
    outline = "#F49B48",
    face = "#F4E1BC",
    effect = "#68CDE0",
    success = "#7ACD84",
    alert = "#EB7070",
  },
  frames = {
    idle_1 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" •ω• ", "face"), S(")", "outline"))
    ),
    blink = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" -ω- ", "face"), S(")", "outline"))
    ),
    focus_1 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" •̀ω•́ ", "face"), S(")", "outline"))
    ),
    curious_1 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" •o• ", "face"), S(")", "outline"), S(" ?", "effect"))
    ),
    curious_2 = F(
      R(S("  "), S("?", "effect"), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" •ω• ", "face"), S(")", "outline"))
    ),
    inspect_1 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" •̀_•́ ", "face"), S(")σ", "outline"), S(" !", "alert"))
    ),
    inspect_2 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" •_• ", "face"), S(")σ", "outline"), S(" ?", "effect"))
    ),
    walk_1 = F(
      R(S("   "), S("(", "outline"), S("•ω•", "face"), S(")ﾉ", "outline"))
    ),
    walk_2 = F(
      R(S("  "), S("ヽ(", "outline"), S("•ω•", "face"), S(")", "outline"))
    ),
    run_1 = F(
      R(S("  "), S("≡", "effect"), S("(", "outline"), S("•̀ω•́", "face"), S(")", "outline"))
    ),
    run_2 = F(
      R(S("  "), S("≡", "effect"), S("(", "outline"), S("•ω•", "face"), S(")›", "outline"))
    ),
    sleep_1 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" -ω- ", "face"), S(")___", "outline")),
      R(S("  "), S("──────────", "outline"))
    ),
    sleep_2 = F(
      R(S("   "), S("/\\_/\\", "outline"), S(" z", "effect")),
      R(S("  "), S("(", "outline"), S(" -ω- ", "face"), S(")___", "outline")),
      R(S("  "), S("──────────", "outline"))
    ),
    appear_1 = F(
      R(S("    "), S("·", "effect"))
    ),
    appear_2 = F(
      R(S("   "), S("⠂·⠄", "effect"))
    ),
    appear_3 = F(
      R(S("   "), S("(", "outline"), S("•ω•", "face"), S(")", "outline"))
    ),
    wave_1 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" •ω• ", "face"), S(")ﾉ", "outline"))
    ),
    wave_2 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" ^ω^ ", "face"), S(")ﾉ", "outline"))
    ),
    cheer_1 = F(
      R(S("  "), S("\\(", "outline"), S(" ^ω^ ", "face"), S(")/", "outline")),
      R(S("     "), S("✦", "success"), S(" "), S("✦", "effect"))
    ),
    magic_1 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S("•ω•", "face"), S(")つ", "outline"), S("✦", "effect"))
    ),
    panic_1 = F(
      R(S("  "), S("!", "alert"), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" >_< ", "face"), S(")", "outline"))
    ),
    peek_1 = F(
      R(S("  "), S("│", "effect"), S("/\\_", "outline")),
      R(S("  "), S("│", "effect"), S("(", "outline"), S("•ω•", "face"))
    ),
    hide_1 = F(
      R(S("  "), S("│", "effect"), S("ω•", "face"), S(")", "outline"))
    ),
    success_1 = F(
      R(S("   "), S("/\\_/\\", "outline")),
      R(S("  "), S("(", "outline"), S(" ^ω^ ", "face"), S(")", "outline"), S(" ✓", "success"))
    ),
  },
  animations = {
    idle = {
      frames = {
        "idle_1", "idle_1", "idle_1", "idle_1", "idle_1", "idle_1",
        "idle_1", "idle_1", "blink", "idle_1",
      },
      loop = true,
    },
    focus = { frames = { "focus_1", "focus_1", "focus_1", "blink" }, loop = true },
    inspect = { frames = { "inspect_1", "inspect_1", "inspect_2", "inspect_1" }, loop = true },
    curious = { frames = { "curious_1", "curious_1", "curious_2", "idle_1" }, loop = true },
    walk = { frames = { "walk_1", "walk_2" }, loop = true },
    run = { frames = { "run_1", "run_2" }, loop = true },
    sleep = { frames = { "sleep_1", "sleep_1", "sleep_2", "sleep_2" }, loop = true },
    appear = { frames = { "appear_1", "appear_2", "appear_3", "idle_1" }, loop = false, next = "idle" },
    vanish = { frames = { "idle_1", "appear_3", "appear_2", "appear_1" }, loop = false },
    wave = { frames = { "wave_1", "wave_2", "wave_1", "idle_1" }, loop = true },
    cheer = { frames = { "cheer_1", "idle_1", "cheer_1", "idle_1" }, loop = true },
    magic = { frames = { "magic_1", "idle_1", "magic_1", "idle_1" }, loop = true },
    panic = { frames = { "panic_1", "idle_1", "panic_1" }, loop = true },
    peek = { frames = { "peek_1", "peek_1", "hide_1", "peek_1" }, loop = true },
    success = { frames = { "success_1", "idle_1", "success_1" }, loop = true },
  },
}
