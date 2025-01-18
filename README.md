# BetterGameMode! A tool for managing Game Mode for macOS

BetterGameMode is a tool for macOS that enhances macOS' Game Mode feature by automatically activating Game Mode in apps & games that do not normally activate Game Mode. It also allows users to manually turn on Game Mode, or force it to be turned off.

Game Mode is a feature of macOS which, when enabled, makes the kernel give high CPU and GPU priority to games, and doubles the Bluetooth polling rate in order to reduce Bluetooth input and output lag. You can read about Game Mode on [Apple’s website](https://support.apple.com/en-us/105118).

Game Mode is supposed to automatically start when the user launches a game. However, this does not happen with every game, most notably, some legacy games, as well as emulators (such as OpenEmu or RetroArch), streaming games (such as GeForce NOW or PS Remote Play), games launched by Wine front ends (such as CrossOver or Whisky), or games running in virtual machines (such as Parallels Desktop or VMware Fusion).

BetterGameMode requires an Apple Silicon Mac, macOS 14.0 (Sonoma) or later, and Xcode 15.0 or later. The Apple Silicon requirement is because Game Mode is not available on Intel Macs. The Xcode requirement is because starting and stopping Game Mode on macOS requires a private API, and the only tool that can use that API is the `gamepolicyctl` tool that comes with Xcode. BetterGameMode requires that tool in order to function. For legal reasons, I cannot ship BetterGameMode with the tool included.

## How to Use BetterGameMode

Once launched, BetterGameMode will add a menu item to your menu bar, that looks like this: ![image-20250115200953979](image-20250115200953979.png)

In this menu bar, you can see if Game Mode is currently on or off, and whether Game Mode is set to start automatically or manually.

By default, Game Mode is off, and starts automatically when you launch a game that Game Mode recognizes. You can force Game Mode on by clicking on **Force Enable Game Mode**, and prevent it from turning on by clicking on **Force Disable Game Mode**. Switch it back to **Automatically Enable Game Mode** to restore the default behavior. This preference does not survive a logout; it will always go back to automatic the next time you sign into your Mac.

## BetterGameMode Settings

Turn on **Automatically launch BetterGameMode on login** to add the app to your login items. I decided to make auto-launch opt-in instead of opt-out.

**Automatically force Game Mode on when one of these apps are launched** is on by default, so unless you turn this off, BetterGameMode will automatically turn on Game Mode when one of the apps in the table below is launched. (This is different from automatic enablement policy. Automatic enablement policy is a feature of macOS where it will automatically turn on Game Mode in certain games. This feature of BetterGameMode allows you to force Game Mode on when an app is launched that does not cause Game Mode to automatically be turned on.)

Press the **+** button to add an app to the list. If there's an app you wish to remove from the list, click on it in the list, and press **-**.

The list is already populated with some common third-party Mac apps that, for whatever reason, macOS does not automatically activate Game Mode when they are launched, but would benefit from Game Mode being on when they are launched.

If you see an app on the list where the name appears in parentheses, then that means the app is not currently installed on your Mac. Feel free to remove it if you wish. If the app is ever (re)installed, then its name will show up on the list.

**Switch Game Mode back to Automatic when none of these apps are running** is also enabled by default, and, while it is enabled, it will automatically switch the Game Mode enablement policy back to Automatic once the last app currently running on the list is quit. But if you want Game Mode to stay on even after the last app is quit for whatever reason, you can switch this off.

That said, I can't recommend keeping Game Mode on long-term, especially on a laptop running on its battery. Turning it off when it's not needed ought to reduce the computer's power usage.

If you want to force Game Mode from ever activating, then disable **Automatically force Game Mode on when one of these apps are launched**, and enable **Automatically force Game Mode off**.