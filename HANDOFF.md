# Handoff — 2026-10-03

## Repository state

- `write-core-integration` is the active web integration branch. Its tip before this handoff was `fd106a2`. This branch and `main` have diverged; the integration work is not on `main`.
- [PR #91](https://github.com/dzackgarza/math-notes-app/pull/91) merged into `write-core-integration` at `deca414`. Its owning issues [#82](https://github.com/dzackgarza/math-notes-app/issues/82) and [#92](https://github.com/dzackgarza/math-notes-app/issues/92) are closed.
- [The merged branch CI run](https://github.com/dzackgarza/math-notes-app/actions/runs/37118272499) passed after shard 6 was rerun. Its first attempt lost a pen stroke in `e2e/research.spec.ts`; that occurrence is recorded on [#72](https://github.com/dzackgarza/math-notes-app/issues/72). The cause is not established.
- [PR #86](https://github.com/dzackgarza/math-notes-app/pull/86) is an open draft from `ipad-port` to `main`. It covers native iPad split view and conflict behavior. The project boundary keeps iPad host work in v2; PR #86 does not represent a merge of the web integration branch.

## Next work unit

`itree next dzackgarza/math-notes-app` names [#72](https://github.com/dzackgarza/math-notes-app/issues/72). Inspect its evidence and the `web-test-results-6` artifact from the first attempt of run `37118272499`. The browser log shows pointer events reaching Flutter before the missing ink check. Work from the issue's acceptance criteria and open its PR when implementation starts.

The remaining roadmap lives under [#11](https://github.com/dzackgarza/math-notes-app/issues/11). The web MVP issue [#56](https://github.com/dzackgarza/math-notes-app/issues/56) is closed. `COMPLAINTS.md` records the interface complaints. [AGENTS.md](AGENTS.md), [README.md](README.md), and [TRAPS.md](TRAPS.md) govern the next work unit.
