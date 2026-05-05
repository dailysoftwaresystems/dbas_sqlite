# Security Policy

## Supported Versions

Security fixes are applied to the latest `2.x` release line. Older
versions are not actively patched — upgrade to the current `2.4.x`
release before reporting issues.

| Version | Supported          |
| ------- | ------------------ |
| 2.4.x   | :white_check_mark: |
| < 2.4   | :x:                |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security reports.** Public
disclosure before a fix is available puts every consumer of this
package at risk.

Email **security@dailysoftwaresystems.com** with:

- A description of the vulnerability and the impact you believe it has.
- Steps to reproduce, or a minimal proof-of-concept.
- The affected version(s) of `dbas_sqlite`.
- Whether you intend to disclose publicly, and on what timeline.

You will receive an acknowledgement within **5 business days**. If
the report is confirmed, we will work with you on coordinated
disclosure: a fix will be prepared, a patched version published to
pub.dev, and a GitHub Security Advisory issued under
[github.com/dailysoftwaresystems/DBAS.SQLite.Flutter/security/advisories](https://github.com/dailysoftwaresystems/DBAS.SQLite.Flutter/security/advisories).

We aim to ship a patched release within **30 days** of confirming
a high-severity report. Lower-severity issues may be rolled into the
next scheduled release.

## Scope

This policy covers vulnerabilities in:

- The `dbas_sqlite` Dart/Flutter plugin code (this repository).
- The native C library binaries that ship inside the published package
  (under `native_libs/` upstream and the platform-specific `ios/`,
  `macos/`, `linux/`, `windows/`, `android/` folders here).

It does **not** cover:

- The upstream SQLite library itself — please report SQLite vulns to
  the SQLite project.
- Vulnerabilities in consumer applications that integrate this plugin.
- Issues in transitive dependencies — report those to the respective
  package maintainers.
