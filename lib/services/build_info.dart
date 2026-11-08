/// Human-visible build stamp, bumped every batch.
///
/// The versionName only moves at release milestones (it sat
/// at the inherited 2.4.3 until batch 77 set Anikumo's own
/// 1.0.0), so support screenshots cannot distinguish builds
/// by version alone — the tenth build was once mistaken for
/// the ninth because of exactly that. The diagnostics pages
/// show this stamp; when a user reports a bug, the stamp in
/// their report pins the build down.
const String kAnikumoBuildStamp = 'B115 · 2026-11-08';
