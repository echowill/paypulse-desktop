# Privacy policy

Applies to the PayPulse Desktop (薪跳) Windows and macOS applications. Last updated: 2026-10-23.

For the Chrome web edition, salary, schedules and preferences are stored in the current browser's local storage and are not uploaded. The website requests static application files from Sites; the hosting platform may process normal request information such as IP addresses. The application does not put salary or schedule data in requests or URLs. See the [web documentation](web/README.md) for web storage and notification behavior.

## Data stays on your device

PayPulse uses the monthly salary, work schedule (including date-specific changes on Mac), goals, and display preferences you enter to estimate earnings. It has no user accounts, advertising, analytics, telemetry, automatic update checks, or network requests. It does not read your other files, monitor your computer activity, or send application data to another system.

The application stores settings locally, without encryption:

- Windows: `%LOCALAPPDATA%\PayPulse\settings.ini`.
- macOS: UserDefaults in the `local.paypulse.mac` preferences domain. Window placement may also be stored locally by macOS.

Mac 1.1.0 also stores floating window, goal and reminder preferences locally. It remembers the last date of a goal celebration to avoid repeating it; it does not maintain a daily earnings history.

Other people or software with access to your local user account may be able to read these settings. Hiding amounts on screen changes their display; it does not encrypt the saved configuration.

## Optional login startup

Login startup is disabled unless you enable it. On Windows this creates or updates the `PayPulse` value under `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`. On macOS the application uses the operating system's login item facility. You can turn this option off in settings.

## Optional local notifications on Mac

Off-work and payday notifications are disabled by default. Enabling them requests macOS notification permission. Future reminder dates and text are scheduled with macOS on this device; notifications contain no salary, earned amount, or goal amount. They do not use a push service or a network connection. In-app goal celebrations also stay local.

To cancel pending reminders, turn off off-work reminders and payday notifications in PayPulse settings and save before quitting or uninstalling. macOS notification settings can also disable their display. Already delivered notifications can be cleared in Notification Center.

## Removing your data

On Windows, disable login startup in settings, exit from the tray menu, delete the extracted application folder, and delete `%LOCALAPPDATA%\PayPulse` if you also want to erase settings. See the [Windows removal instructions](windows/README.md#卸载与清理).

On macOS, disable login startup, quit PayPulse, remove the app, and remove its `local.paypulse.mac` preferences if you want to erase its settings.

## External services

GitHub hosts the source and downloads. Its website and download services are subject to [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). The PayPulse application does not contact GitHub at runtime.

The application to use SignPath Foundation for Windows code signing was not approved and integration is on hold. A future signing integration would involve maintainer account details and public build artifacts, not end-user salary or schedule data. See [SignPath's privacy policy](https://signpath.io/privacy-policy) and our [Code signing policy](CODE_SIGNING_POLICY.md).

## Questions

For application privacy questions, contact the maintainer through [GitHub Issues](https://github.com/echowill/paypulse-desktop/issues). Issues are public; do not include your salary, configuration file, or other private information.
