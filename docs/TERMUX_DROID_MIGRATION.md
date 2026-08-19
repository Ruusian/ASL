# TermuxDroid Migration and Improvement Notes

ASL is the canonical merged project. TermuxDroid's desktop and container
workflow is represented through `asl termux-droid`, while ASL remains the
single owner of root/proot detection, mounts, desktop state, GPU setup, and
process cleanup.

## Feature Mapping

| TermuxDroid capability | ASL entry point |
| --- | --- |
| XFCE4 and Termux:X11 desktop | `asl desktop start` |
| Root or proot container | `asl start`, `asl exec-mode`, `asl doctor` |
| Stop desktop and Linux session | `asl termux-droid stop` |
| Proot application menu sync | `asl desktop sync-apps` or `asl termux-droid sync-apps` |
| GPU profile selection | `asl gpu` and `asl mode` |
| Raspberry Pi monitor bridge | `desktop/pi-bridge.sh` |

## Improvements Made

- Removed the need for two independent desktop lifecycle implementations.
- Reused ASL's stateful process tracking and guarded cleanup instead of broad
  `pkill -f` patterns.
- Reused ASL's desktop-entry validation and launcher ownership markers for app
  synchronization.
- Added a stable compatibility command so existing TermuxDroid users have a
  migration path without maintaining duplicate rootfs configuration.
- Added a focused Pi bridge with bounded retries and required-command checks.

## Follow-up Improvements

1. Move remaining installer-only provisioning into modular ASL installer steps
   rather than embedding large generated scripts in one setup file.
2. Add Android-device integration tests for Termux:X11, GPU library binding,
   PulseAudio, and root/proot transitions; the current tests are host-side.
3. Add a release migration notice to TermuxDroid that points users to ASL and
   clearly explains the supported command mapping.
4. Resolve licensing before copying additional TermuxDroid source. TermuxDroid
   is GPL-3.0-only, while ASL currently declares MIT; adapted functionality and
   any copied code must retain the applicable license and attribution.
