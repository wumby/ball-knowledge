# Ball Knowledge development guidance

This is primarily a native SwiftUI iOS app. Do not run web-development tooling for iOS app changes.

The `Website/` directory is an isolated Svelte + Vite marketing site. For work scoped to that directory, `npm install`, `npm run dev`, and `npm run build` are allowed. Start its development server from `Website/` only, and stop it when it is no longer needed.

## Before handing off a change

Build the app for the simulator:

```sh
xcodebuild -project BallKnowledge.xcodeproj -scheme BallKnowledge -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

When code or behavior changes, run the test suite on an available simulator (use `xcrun simctl list devices available` to find one):

```sh
xcodebuild test -project BallKnowledge.xcodeproj -scheme BallKnowledgeTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

If the named simulator is unavailable, choose another available iPhone simulator rather than skipping tests.

## Swift/iOS practices

- Keep GameKit and network cleanup asynchronous; persist local gameplay and ranked state before any external submission or navigation.
- Preserve `@MainActor` boundaries for observable UI services and use detached tasks only for immutable, CPU-heavy archive work.
- Do not use destructive Git commands to discard an existing dirty worktree.
- Keep historical NBA identity rules centralized in `NBAFranchiseIdentity`; comparison and eligibility code must not introduce local alias maps.
- For ranked changes, preserve exactly-once local MMR mutation semantics and test season-reset/relaunch behavior.
