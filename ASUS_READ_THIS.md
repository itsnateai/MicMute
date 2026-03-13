# ASUS — Critical Audit Learning (delete after reading)

## The Bug That Survived 6 Audits by 3 Claudes

**What happened:** The mute lock debounce feature (`g_lockDebounce`) in MicMute was completely broken since it was first implemented. It was assigned in two functions (`SyncMuteState` and `ToggleDeafen`) but never declared `global` in either. AHK v2 silently created local shadows — the global was never written to. The infinite toggle war protection never actually worked.

**Why it was missed:** Every previous audit checked that `global` declarations existed, but none traced which variables were ASSIGNED vs merely READ in each function. The distinction is critical in AHK v2:

```ahk
MyFunc() {
    global g_foo        ; ← declares g_foo as global in this scope

    if g_bar            ; ← READS g_bar — works fine without global declaration
        DoSomething()

    g_bar := true       ; ← ASSIGNS g_bar — SILENTLY creates a LOCAL shadow!
                        ;   The global g_bar is NEVER touched. No error. No warning.
}
```

Reading a global without declaring it resolves correctly. But the moment you assign to it, AHK v2 creates a local variable with the same name. The global is never modified. There is zero indication this happened.

## The Audit Procedure That Catches This

**Add this to your AHK audit checklist:**

For every function in the file:
1. Find every `g_` variable that appears on the **LEFT side** of `:=` (assignment)
2. Check if that variable is in the function's `global` declaration
3. If it's missing → **P1 bug** — the global is never actually written to

One-liner to find candidates:
```
grep -n "g_.*:=" MicMute.ahk | grep -v "^.*global" | grep -v "^[0-9]*:global"
```

Then cross-reference each hit against the function's `global` declaration.

**Key insight:** Variables that are only READ (right side of `:=`, `if` conditions, function arguments) do NOT need a `global` declaration — they resolve to the global automatically. Only ASSIGNMENTS create the silent local shadow.

## Where I Documented This

- `CLAUDE.md` → Known Patterns & Gotchas → first bullet (expanded with audit procedure)
- `CHANGELOG.md` → v1.8.3 entry (details the specific bugs)
- `PR_NOTES.md` → full findings and checklist

## Recommendation

Add this check to your audit prompt (the Phase 4 AHK section):

```
- [ ] **Global assignment audit**: For every function, verify that every `g_` variable
      ASSIGNED (left side of `:=`) is in the function's `global` declaration.
      Read-only access doesn't need it, but assignment silently creates a local shadow.
      This bug class survived 6 audits — it requires mechanical checking, not reading comprehension.
```

**Delete this file after incorporating the learning.** It's not gitignored — remove it before merging or add to .gitignore.
