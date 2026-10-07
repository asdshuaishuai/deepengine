# Scene 001 — AI-native engine probe

This file is the single source of truth for the scene below. Only ops inside
`mbg` fences are executed; all prose and headings are ignored by the runtime —
the same convention moonviz uses for `.mbt.md`.

An agent edits ops here; the runtime hot-reloads on file change (no restart).

```mbg
# canvas
bg 11 13 19

# hero card
rect card 72 96 460 236 #191e2c 28
rect card_accent 72 96 6 236 #e5484d 3
text title 112 136 40 #eef1f7 "AI-native game engine"
text sub 112 194 19 #8b93a7 "declarative scene -> raylib runtime"
text meta 112 236 16 #59607a "hot reload - deterministic frames - agent writable"

# orbiting particles around a hub
circle hub 0 0 10 #f5a524
orbit hub 880 300 0 0 0
circle orb1 0 0 8 #30a46c
orbit orb1 880 300 150 60 0
circle orb2 0 0 6 #e5484d
orbit orb2 880 300 200 -45 1.6
circle orb3 0 0 11 #7c66dc
orbit orb3 880 300 250 28 2.4

# spinning sprite + pulse
sprite logo 1020 600 112 #3b82f6
spin logo 22
pulse logo 0.92 1.12 0.25

# baseline
line rule 72 560 1208 560 2 #232a3d
text hint 72 590 17 #4a5163 "keys: R reload   S shot   3 3d mode   space pause   esc quit"
```
