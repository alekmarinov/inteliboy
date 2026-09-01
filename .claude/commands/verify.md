Verify the current state of every component. Do not change anything.

1. `make status` — branch, dirty count and unpushed count per component.
2. `make test` — each component's own test command. Read the real output.
3. Compare the dirty list against any open brief under `changes/`.

Report, in this order:
- anything dirty that no open brief accounts for (this is the important one);
- anything whose tests fail, with the actual failure, not a summary;
- anything whose `test` field in `components.toml` is empty, named plainly as
  unverifiable rather than as passing;
- whether `versions.lock` matches the current HEADs.

Do not fix anything you find. Report it and stop.
