# Portable Folder Icons

Portable Folder Icons adds a nested **Folder Icons** menu to Windows Explorer
so you can apply a bundled or custom ICO to one folder at a time. It installs
for the current user only and uses the classic context menu available through
**Show more options** on Windows 11.

## Requirements

- Windows 10 or Windows 11
- A normal, non-administrator user session
- Inbox Windows PowerShell 5.1

Python, a virtual environment, downloads, third-party packages, administrator
rights, and an Explorer restart are not required.

## Setup

1. Copy or extract the whole repository anywhere writable under your Windows
   user profile.
2. Double-click `Setup_and_Run-Portable-Folder-Icons.bat`.
3. Review the icon-results table and final installed paths, then press Enter
   to close.

Windows SmartScreen or workplace security software may warn about an unsigned
download on the first run. If you trust this copy, choose **More info** and
then **Run anyway**. The launcher refuses to run elevated; do not choose
**Run as administrator**.

Setup validates each immediate `.ico` file in `files\ICO-Files`, copies valid
content to a SHA-256-named cache, installs a self-contained runtime under
`%LOCALAPPDATA%\Portable-Folder-Icons`, and creates the current-user menu.
Rerunning the batch is a safe install/update/repair/rescan operation.

## Use

1. Right-click one normal writable folder.
2. On Windows 11, choose **Show more options**.
3. Open **Folder Icons** and choose an icon.

Apply and Reset show a short progress terminal while the customization is
committed and the matching parent Explorer view is reloaded. That view returns
to the same folder automatically; its selection and scroll position may reset.
The tool never restarts Explorer or globally rebuilds the icon cache.

The submenu also includes:

- **Reset to Default** — removes only folder-icon fields while preserving
  unrelated `desktop.ini` customization.
- **Repair Portable Folder Icons** — validates the installed runtime,
  manifest, and referenced cache, then recreates the menu. Repair works after
  the repository is moved or removed, but it does not import new source icons.
- **Uninstall Portable Folder Icons** — requires confirmation, removes the
  menu/runtime/active manifest, and preserves hashed cached icons by default
  so folders already using them do not break. A separate purge prompt warns
  before cache deletion.

## Add or update icons

Place immediate `.ico` files in `files\ICO-Files` and rerun the setup batch.
Subfolders are not scanned. Labels come from filenames: `Folder_Blue.ico`
becomes **Blue**, underscores become spaces, and other capitalization is
preserved.

Invalid, empty, unreadable, or malformed ICOs are rejected individually.
Different files that normalize to the same label are both omitted until
renamed. Replacing or renaming a source icon does not delete the old hashed
cache, so previously customized folders keep their icon.

## Limitations

- One selected folder at a time; multi-selection is planned for a future
  version.
- Windows 10/11 local NTFS and ReFS folders only.
- Filesystem roots, UNC/network paths, Windows system folders, protected
  application folders, and locations you cannot write are rejected.
- The menu is in the classic context menu, not Windows 11's first compact
  menu.
- The matching parent view is navigated out and back automatically to force a
  full reload. Its window and final location are preserved, but selection,
  scroll position, and Back history are not guaranteed.

## Troubleshooting

- **No menu:** rerun setup normally. If the repository is unavailable, use the
  installed Repair command.
- **Icon rejected during setup:** read its row in the results table. Confirm it
  is a real, readable, non-empty ICO and that its normalized label is unique.
- **Apply reports a missing/corrupt cache:** run Repair for a precise integrity
  report, then rerun repository setup if source icons need to be reimported.
- **Access denied/protected folder:** choose a normal folder you own. Do not
  elevate the launcher.
- **Apply reports that refresh failed:** the customization was saved, but the
  targeted Explorer reload did not complete. Reopen that parent location and
  report the warning text.

## License and icon rights

The code and the ten bundled ICO assets are covered by the root MIT license;
the copyright holder has confirmed redistribution permission for those
assets. Icons later added by individual users remain their responsibility and
are not automatically granted redistribution rights by this repository.
