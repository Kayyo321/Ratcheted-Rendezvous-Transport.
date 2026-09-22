# Development workflow

## Repository branch hygiene

The canonical remote branch is `origin`. Keep local work on a descriptive
branch (for example, `codex/fix-version-control`) and verify its upstream
with `git branch -vv`. Do not name a local branch `origin` or configure an
upstream such as `refs/heads/heads/origin`; those names make Git and hosting
UIs display misleading ahead/behind status. If an accidental remote branch
named `heads/origin` exists, remove it after confirming that `origin` contains
the intended history.

RRT changes use small, single-purpose commits. Each commit contains one coherent modification: a protocol primitive, a validation rule, a test vector, a build adjustment, or a documentation update. Avoid mixing refactors, behavior changes, generated files, and formatting-only changes in the same commit.

## Change loop

1. Inspect the working tree before editing:

   ```sh
   git status --short
   git log --oneline -8
   ```

2. Make one narrowly scoped change. Preserve unrelated user changes. A dirty
   working tree is not a reason to combine independent work: use selective
   staging (`git add path/to/file` or `git add -p`) so the current commit
   contains only that one change.

3. Format only the files changed by that work:

   ```sh
   zig fmt src/path/to/file.zig tests/path/to/file.zig
   ```

4. Run the smallest relevant verification first, then the full project checks when the change affects shared code:

   ```sh
   zig build test
   zig build fmt-check
   zig build -Doptimize=ReleaseSafe
   ```

5. Inspect the staged diff and commit immediately with an imperative, scoped message.
   Do not begin the next independent change until the staged diff contains one
   coherent behavior and has been committed. If a change touches several
   concerns (for example, encoding, storage, IPC, and trust), split it into
   separate commits even when the working tree already contains user edits:

   ```sh
   git add src/path/to/file.zig tests/path/to/file.zig
   git diff --cached --check
   git diff --cached
   git commit -m "feat: reject invalid relay route"
   ```

6. Repeat from a clean working tree. Documentation changes that describe completed behavior are committed separately from implementation changes unless they are inseparable from a public interface change.

When the tree cannot be made clean because it contains user work, repeat from
an unchanged user baseline and keep every agent-authored commit selectively
staged, single-purpose, and independently buildable. Never use unrelated dirty
files as justification for a broad “foundation” commit.

## Commit conventions

Use a short category followed by a precise summary:

- `feat:` — a new enforced behavior
- `fix:` — a corrected behavior
- `test:` — tests or vectors only
- `docs:` — documentation only
- `build:` — build, tooling, or CI only
- `refactor:` — no behavior change

Every commit must build independently and must not claim a security property that its code and tests do not enforce. Security-sensitive changes include a negative test for the rejected condition. Do not accumulate unrelated edits for a later “cleanup” commit.
