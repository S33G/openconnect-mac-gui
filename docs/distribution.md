# Distribution

Local builds are ad-hoc signed development apps. Dependencies are installed separately. To produce a distribution installer, supply your own Developer ID identities and configured notarytool profile:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
INSTALLER_IDENTITY='Developer ID Installer: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' \
scripts/package-release.sh
```

The script signs the app, notarizes/staples it, builds the installer, and notarizes/staples that installer. No credentials are included in the repository. The optional `BUNDLE_ID` build variable can set your distribution identity; align managed preferences with it.

Builds target the current Mac architecture. Qualify Intel/Apple Silicon, fresh accounts, dependency installation, normal and background sessions, teardown, and hardened-runtime execution before advertising support. No native service is installed by the background-session implementation.
