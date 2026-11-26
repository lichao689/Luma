# P0 / P1 review

The first implementation was reviewed against baseline `d122d3e6f10e77bffe19d523b4d51682146fc060`. Local review commit `dd6e8c3` and published commit `9205869` have the identical Git tree `11b2e60c32c7d6159feebab86f890db71b4304b8`. The originating contract is [p0-p1.md](p0-p1.md). Standards and specification reviews were performed separately.

## Standards

No hard violation of a documented repository coding standard was identified. Two maintenance concerns had concrete effects and were addressed:

1. **Duplicated health merge decisions.** The write-time projection initially checked workouts while the display-time merger additionally checked sleep and steps. Conflicting same-time step observations could be saved successfully and then fail to display. `BackupHealthProjection` now validates the complete archived observation set before any persistence and supplies the same aggregation path to `WorkoutStore.healthSnapshot`. Regression tests cover same-time conflicts and older carried-forward samples. A failed import must leave the store unchanged.
2. **Scattered error translations.** Some typed logic errors carried Chinese-only or bilingual diagnostic text, which leaked into the English app. `UserFacingError.swift` now maps all domain error cases to app localization resources, preserving parameters and falling back to system-localized errors. The portable logic keeps its typed errors and remains independent of the UI.

The first Apple build also exposed a type-checker timeout in the old chained `map/sorted/reduce(nil)` health aggregation. The shared, explicitly typed aggregation introduced for the first finding removes that expression.

## Spec

No unaddressed definite specification defect remained after review fixes. The review found and verified these corrections:

- Recovery recommendations now suppress flexible and weekly strength nudges through a shared `ReminderPolicy` gate.
- Source-proven Health running updates can converge across backups; a latest source correction to another activity removes the derived running record without fabricating a permanent deletion.
- Restore/sync previews show updated source-derived sessions, while conflicting manual records are still rejected.
- Plan editing clears stale saved-state presentation, retains the original plan identity when a save-copy operation fails, and initializes the displayed template budget from the selected plan.
- Workout history lookup is cached on step/store changes instead of querying the entire database on every timer tick.

No clear out-of-scope product behavior was found. The iPhone file bridge and manual shared-folder exchange are explicit implementation choices in the contract.

## Verification boundaries

Portable tests and the pull request's Apple SDK jobs provide automated evidence. Device acceptance remains separate: Health read permissions and source deletion propagation, existing SwiftData store migration, real notification actions/escalation, window/sleep lifecycle, and two-Mac folder-provider propagation. The checklist in the implementation contract does not claim those device steps have been performed.

Review totals: Standards — zero hard violations, two concerns resolved; Spec — zero remaining definite defects, device acceptance still required.
