# Contributing

Thanks for taking a look. Help is welcome, whether that's a bug report, a
fix, a test or just pointing out something in the docs that didn't make
sense.

## Where help is most useful

- Bug fixes.
- Tests for platform edge cases. Lifecycle behavior differs a lot between
  Android, iOS, desktop and web, and every real-world case that ends up in
  a test is a win.
- Reports from real devices, especially around iOS background time and
  Android apps coming back after being killed. I can't test every device
  myself.
- Typos, unclear docs, missing examples.

## Talk to me first

For anything bigger than a small fix, please open an issue before you write
the code. That way we can agree on the approach and you don't spend time on
something I end up asking you to change.

This matters most for:

- New public API. I'd like to keep the API small, so new methods or
  widgets need a good reason.
- New dependencies. Right now the package only depends on Flutter, and I'd
  like to keep it that way.
- Anything that changes existing behavior.

## Getting set up

```sh
git clone https://github.com/ebrahimmansur/lifescope.git
cd lifescope
flutter pub get
flutter test
```

Before opening a PR, make sure these pass:

```sh
dart format .
flutter analyze
flutter test
```

## Guidelines

- Keep PRs focused on one thing. Two small PRs are easier to review than
  one big one.
- If you change behavior, add a test. The tests in `test/` drive the real
  binding with `tester.binding.handleAppLifecycleStateChanged` and
  `handleRequestAppExit`, and `test/mobile_test.dart` shows how to send
  messages the way Android and iOS do. Copy from there.
- Public members need a doc comment. The analyzer will remind you.
- For changes users will notice, add a line under `## Unreleased` at the
  top of `CHANGELOG.md` (create that heading if it isn't there yet).
- No breaking changes without talking about it first.

## iOS code

The only native code is in `ios/lifescope/Sources/lifescope/`. If you touch
it, please test on a real device. The simulator doesn't suspend apps the
same way, so background time issues often don't show up there.

## Releases

I take care of version numbers and publishing to pub.dev, so you don't
need to bump the version in your PR.
