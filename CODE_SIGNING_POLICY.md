# Code signing policy

PayPulse Desktop (薪跳) is maintained at [echowill/paypulse-desktop](https://github.com/echowill/paypulse-desktop) under the [MIT license](LICENSE).

## Current status

We are preparing an application for free code signing through [SignPath Foundation](https://signpath.org/). The application has not been approved, signing is not configured, and the current Windows releases are unsigned. This policy does not claim that any existing release has a SignPath signature.

If the application is approved and signing becomes available, signed releases will carry this attribution:

> Free code signing provided by [SignPath.io](https://signpath.io/), certificate by [SignPath Foundation](https://signpath.org/).

This application concerns the Windows `PayPulse.exe` binary. macOS signing and notarization are outside its scope.

## Team roles

| Role | Maintainer | Responsibility |
| --- | --- | --- |
| Author / committer | [echowill](https://github.com/echowill) | Maintain project source and build scripts. |
| Reviewer | [echowill](https://github.com/echowill) | Review external contributions, including changes to build and signing configuration. |
| Signing approver | [echowill](https://github.com/echowill) | Manually approve each release signing request after reviewing source, build results, and artifacts. |

Contributors without commit permission must submit changes for review. Before signing is enabled, all project members with source or signing access must use multi-factor authentication for GitHub and SignPath, as required by the [Foundation conditions](https://signpath.org/terms).

## Planned signing process

- Build only this project's own source from an identified commit in the public repository, using GitHub Actions and SignPath origin verification.
- Require successful core and native Windows UI checks before requesting release signing.
- Restrict signing to the project's `PayPulse.exe`; enforce product name `PayPulse`, the intended product version, and the approved artifact paths in SignPath configuration. Do not accept arbitrary uploaded executables.
- Require manual approval for every release signing request. Keep signing credentials outside source control and restrict their access.
- Verify the returned Authenticode signature and run the signed artifact's checks before publishing it. Generate download checksums after signing; do not modify the executable afterward.
- Update release notes to identify signed files and their publisher. Existing unsigned releases retain their existing status.

## Privacy and system changes

PayPulse makes no network requests and does not send salary, schedule, configuration, or device data to any service. See the [Privacy policy](PRIVACY.md).

Windows login startup is opt-in and changes only the current user's startup entry. The app is portable; see the [removal instructions](windows/README.md#卸载与清理) to disable startup, exit, and remove local files. SignPath would process maintainer account information and build artifacts for signing, not users' salary settings.
