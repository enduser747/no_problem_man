# no_problem_man v1.0 — Windows Startup Control

A lightweight graphical utility for reviewing and disabling recognized optional startup apps on Windows 10/11. Built on the first working WinCare Startup core.

## How to run
1. Extract **all files** from the ZIP into the same folder.
2. Double-click `START.cmd` and approve the Windows administrator prompt.
3. In the window, choose **Optimize Startup** to apply changes, or **Restore** to restore a compatible backup.

The included `DIAGNOSTICS.cmd` is only for investigating launch failures. Do not run it for normal use.

## Scope and limitations
- Uses an allowlist of known applications; unknown items are left unchanged.
- Covers selected Run keys, Startup shortcuts and compatible scheduled tasks; some recognized emulator updater services may also be affected.
- Does not uninstall software or forcibly stop active apps. Does not require network access.
- Backup data is kept under `%ProgramData%\no_problem_man\Backups`.
- Running with administrator rights affects system startup settings. **Tested by the author on one Windows machine; not comprehensively validated across Windows 10/11 configurations.** Review the source and back up important data before use.

## Українською

**no_problem_man v1.0** — графічна утиліта керування автозавантаженням Windows 10/11 на основі першої робочої WinCare Startup.

**Запуск:** розпакуйте **усі файли** в одну папку, двічі натисніть `START.cmd` та підтвердьте права адміністратора. У вікні натисніть **Оптимізувати автозапуск** або **Відновити**. `DIAGNOSTICS.cmd` потрібен лише для пошуку помилок запуску.

**Межі роботи:** програма розпізнає лише визначені необов'язкові застосунки, інші залишає без змін. Опрацьовує певні записи реєстру Run, ярлики Startup, сумісні завдання Планувальника та деякі визначені служби оновлення емуляторів. Програми не видаляє, активні процеси примусово не завершує, мережа не потрібна. Резервні копії — у `%ProgramData%\no_problem_man\Backups`.

**Статус:** автор підтвердив роботу на одному комп'ютері з Windows; масштабної перевірки на різних конфігураціях Windows 10/11 ще не було. Програма працює з правами адміністратора, тому перед використанням рекомендовано переглянути відкритий код та зберегти важливі дані.
