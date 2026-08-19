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
  id = "spirit",
  kind = "glyph",
  version = 1,
  width = 14,
  height = 3,
  palette = {
    outline = "#9AD8E8",
    face = "#E9F3F4",
    effect = "#C7A7FF",
    success = "#9DDB9A",
    alert = "#F08B8B",
    muted = "#778B91",
  },

  frames = {
    idle = F(
      R(S("     "), S("✦", "effect")),
      R(S("   "), S("~(", "outline"), S("•ᴗ•", "face"), S(")~", "outline"))
    ),
    idle_soft = F(
      R(S("     "), S("·", "effect")),
      R(S("   "), S("~(", "outline"), S("˘ᴗ˘", "face"), S(")~", "outline"))
    ),
    blink = F(
      R(S("     "), S("✦", "effect")),
      R(S("   "), S("~(", "outline"), S("-ᴗ-", "face"), S(")~", "outline"))
    ),
    focus = F(
      R(S("     "), S("◇", "effect")),
      R(S("   "), S("~(", "outline"), S("•̀_•́", "face"), S(")~", "outline"))
    ),
    visual = F(
      R(S("     "), S("·", "effect")),
      R(S("   "), S("(", "outline"), S("•_•", "face"), S(")σ", "outline"), S(" ·", "effect"))
    ),
    operator = F(
      R(S("    "), S("⌁", "effect"), S("✦", "effect")),
      R(S("   "), S("~(", "outline"), S("•̀ᴗ•́", "face"), S(")~", "outline"))
    ),
    replace = F(
      R(S("    "), S("!", "alert"), S("◇", "effect")),
      R(S("   "), S("~(", "outline"), S("•̀_•́", "face"), S(")~", "outline"))
    ),
    command = F(R(S("   "), S("⌁(", "effect"), S("•ᴗ•", "face"), S(")⌁", "effect"))),
    terminal = F(R(S("   "), S("~(", "outline"), S("•ᴗ•", "face"), S(")~", "outline"))),
    curious_1 = F(
      R(S("   "), S("?", "effect"), S("  ✦", "effect")),
      R(S("   "), S("~(", "outline"), S("•o•", "face"), S(")~", "outline"))
    ),
    curious_2 = F(
      R(S("     "), S("✦", "effect"), S(" ?", "effect")),
      R(S("   "), S("~(", "outline"), S("•ᴗ•", "face"), S(")~", "outline"))
    ),
    inspect_1 = F(
      R(S("     "), S("◇", "effect")),
      R(S("   "), S("(", "outline"), S("•̀_•́", "face"), S(")σ", "outline"), S(" !", "alert"))
    ),
    inspect_2 = F(
      R(S("     "), S("·", "effect")),
      R(S("   "), S("(", "outline"), S("•_•", "face"), S(")σ", "outline"), S(" ?", "effect"))
    ),
    glance_l = F(
      R(S("     "), S("✦", "effect")),
      R(S("   "), S("~(", "outline"), S("¬ᴗ•", "face"), S(")~", "outline"))
    ),
    glance_r = F(
      R(S("     "), S("✦", "effect")),
      R(S("   "), S("~(", "outline"), S("•ᴗ¬", "face"), S(")~", "outline"))
    ),
    shimmer = F(
      R(S("   "), S("·", "effect"), S(" ✦ ", "success"), S("·", "effect")),
      R(S("   "), S("~(", "outline"), S("•ᴗ•", "face"), S(")~", "outline"))
    ),
    stretch = F(
      R(S("  "), S("⌁╰(", "outline"), S("^ᴗ^", "face"), S(")╯⌁", "outline")),
      R(S("     "), S("·", "effect"))
    ),
    walk_1 = F(R(S("  "), S("⠂", "effect"), S("~(", "outline"), S("•ᴗ•", "face"), S(")", "outline"))),
    walk_2 = F(R(S("   "), S("(", "outline"), S("•ᴗ•", "face"), S(")~", "outline"))),
    run_1 = F(R(S(" "), S("≡", "effect"), S("(", "outline"), S("•̀ᴗ•́", "face"), S(")~", "outline"))),
    run_2 = F(R(S("   "), S("~(", "outline"), S("•ᴗ•", "face"), S(")›", "outline"))),
    dash_1 = F(R(S(" "), S("⠂⠄≡", "effect"), S("(", "outline"), S("•̀ᴗ•́", "face"), S(")›", "outline"))),
    dash_2 = F(R(S("  "), S("≡", "effect"), S("~(", "outline"), S("•ᴗ•", "face"), S(")", "outline"))),
    sleep_1 = F(
      R(S("     "), S("·", "effect")),
      R(S("   "), S("~(", "outline"), S("-ᴗ-", "face"), S(")~", "outline")),
      R(S("    "), S("~~~~~", "muted"))
    ),
    sleep_2 = F(
      R(S("     "), S("·", "effect"), S(" z", "effect")),
      R(S("   "), S("~(", "outline"), S("-ᴗ-", "face"), S(")~", "outline")),
      R(S("    "), S("~~~~~", "muted"))
    ),
    appear_1 = F(R(S("     "), S("·", "effect"))),
    appear_2 = F(R(S("    "), S("⠂✦⠄", "effect"))),
    appear_3 = F(R(S("   "), S("~(", "outline"), S("•ᴗ•", "face"), S(")~", "outline"))),
    wave_1 = F(
      R(S("     "), S("✦", "effect")),
      R(S("   "), S("(", "outline"), S("•ᴗ•", "face"), S(")ﾉ", "outline"))
    ),
    wave_2 = F(
      R(S("     "), S("✦", "success")),
      R(S("   "), S("(", "outline"), S("^ᴗ^", "face"), S(")ﾉ", "outline"))
    ),
    cheer = F(
      R(S("   "), S("✦", "success"), S("   "), S("✦", "effect")),
      R(S("  "), S("╰(", "outline"), S("^ᴗ^", "face"), S(")╯", "outline"))
    ),
    magic = F(
      R(S("     "), S("◇", "effect")),
      R(S("   "), S("(", "outline"), S("•ᴗ•", "face"), S(")つ", "outline"), S("✦", "effect"))
    ),
    panic = F(
      R(S("    "), S("!", "alert"), S("✦", "effect")),
      R(S("   "), S("~(", "outline"), S(">_<", "face"), S(")~", "outline"))
    ),
    peek_1 = F(
      R(S("  "), S("│", "effect"), S(" ✦", "effect")),
      R(S("  "), S("│", "effect"), S("(", "outline"), S("•ᴗ•", "face"))
    ),
    peek_2 = F(R(S("  "), S("│", "effect"), S("ᴗ•)", "face"))),
    success = F(
      R(S("   "), S("✦", "success"), S("  ✦", "success")),
      R(S("   "), S("~(", "outline"), S("^ᴗ^", "face"), S(")~", "outline"), S(" ✓", "success"))
    ),
    save = F(
      R(S("     "), S("✦", "success")),
      R(S("   "), S("~(", "outline"), S("˘ᴗ˘", "face"), S(")~", "outline"))
    ),
  },

  poses = {
    idle = "idle",
    focus = "focus",
    visual = "visual",
    operator = "operator",
    replace = "replace",
    command = "command",
    terminal = "terminal",
    curious = "curious_1",
    inspect = "inspect_1",
    sleep = "sleep_1",
  },

  motion = {
    walk = { "walk_1", "walk_2" },
    run = { "run_1", "run_2" },
    dash = { "dash_1", "dash_2" },
  },

  animations = {
    idle = { steps = { { frame = "idle", duration_ms = 1000 } }, loop = true },
    focus = { steps = { { frame = "focus", duration_ms = 1000 } }, loop = true },
    inspect = {
      steps = {
        { frame = "inspect_1", duration_ms = 330 },
        { frame = "inspect_2", duration_ms = 260 },
      },
      loop = true,
    },
    curious = {
      steps = {
        { frame = "curious_1", duration_ms = 300 },
        { frame = "curious_2", duration_ms = 300 },
        { frame = "idle", duration_ms = 190 },
      },
      loop = true,
    },
    sleep = {
      steps = {
        { frame = "sleep_1", duration_ms = 760 },
        { frame = "sleep_2", duration_ms = 760 },
      },
      loop = true,
    },
    blink = {
      steps = {
        { frame = "blink", duration_ms = 70 },
        { frame = "idle", duration_ms = 90 },
      },
    },
    glance = {
      steps = {
        { frame = "glance_l", duration_ms = 250 },
        { frame = "idle", duration_ms = 100 },
        { frame = "glance_r", duration_ms = 250 },
        { frame = "idle", duration_ms = 120 },
      },
    },
    ear_twitch = {
      steps = {
        { frame = "shimmer", duration_ms = 130 },
        { frame = "idle", duration_ms = 130 },
        { frame = "shimmer", duration_ms = 100 },
        { frame = "idle", duration_ms = 120 },
      },
    },
    stretch = {
      steps = {
        { frame = "idle_soft", duration_ms = 170 },
        { frame = "stretch", duration_ms = 400 },
        { frame = "idle", duration_ms = 180 },
      },
    },
    appear = {
      steps = {
        { frame = "appear_1", duration_ms = 45 },
        { frame = "appear_2", duration_ms = 55 },
        { frame = "appear_3", duration_ms = 60 },
        { frame = "idle", duration_ms = 70 },
      },
    },
    vanish = {
      steps = {
        { frame = "appear_3", duration_ms = 55 },
        { frame = "appear_2", duration_ms = 50 },
        { frame = "appear_1", duration_ms = 45 },
      },
    },
    wave = {
      steps = {
        { frame = "wave_1", duration_ms = 180 },
        { frame = "wave_2", duration_ms = 180 },
        { frame = "wave_1", duration_ms = 160 },
        { frame = "idle", duration_ms = 160 },
      },
    },
    cheer = {
      steps = {
        { frame = "cheer", duration_ms = 260 },
        { frame = "idle_soft", duration_ms = 160 },
        { frame = "cheer", duration_ms = 230 },
        { frame = "idle", duration_ms = 170 },
      },
    },
    magic = {
      steps = {
        { frame = "magic", duration_ms = 260 },
        { frame = "shimmer", duration_ms = 150 },
        { frame = "magic", duration_ms = 220 },
        { frame = "idle", duration_ms = 160 },
      },
    },
    panic = {
      steps = {
        { frame = "panic", duration_ms = 170 },
        { frame = "idle", duration_ms = 120 },
        { frame = "panic", duration_ms = 170 },
      },
    },
    peek = {
      steps = {
        { frame = "peek_2", duration_ms = 130 },
        { frame = "peek_1", duration_ms = 310 },
        { frame = "peek_2", duration_ms = 160 },
      },
      loop = true,
    },
    success = {
      steps = {
        { frame = "success", duration_ms = 360 },
        { frame = "idle_soft", duration_ms = 180 },
      },
    },
    save = {
      steps = {
        { frame = "save", duration_ms = 320 },
        { frame = "idle_soft", duration_ms = 160 },
      },
    },
  },
}
