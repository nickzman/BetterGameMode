//
//  AppDelegate.swift
//  BetterGameMode
//
//  Created by Nick Zitzmann on 12/27/24.
//
// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// 3. The name of the author may not be used to endorse or promote products derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Cocoa
import os.log
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
	private enum IsGamePolicyCtlInstalled: Int {
		case unknown		// we haven't checked yet, or our attempt to check failed
		case notInstalled	// gamepolicyctl is not installed; user needs to install Xcode
		case installed		// gamepolicyctl is installed
	}
	private enum GameModeEnablementPolicy: Int {
		case unknown	// we haven't checked yet, or our attempt to check failed
		case automatic	// macOS will automatically start Game Mode when the user launches a game full screen
		case disabled	// macOS will not automatically start Game Mode
	}
	private enum IsGameModeEnabled: Int {
		case unknown			// we haven't checked yet, or our attempt to check failed
		case disabled			// Game Mode has been manually disabled
		case enabled			// Game Mode has been automatically or manually enabled
		case temporarilyEnabled	// Game Mode is enabled right now, but will disable after a timeout (this usually happens when a game that automatically started Game Mode is put in the background)
	}
	private var appLaunchedNotificationObserver: NSObjectProtocol?
	private var appTerminatedNotificationObserver: NSObjectProtocol?
	
	private var appsThatEnableGameMode: Set<NSRunningApplication> = []
	private var enablementPolicy: GameModeEnablementPolicy = .unknown
	private var gameMode: IsGameModeEnabled = .unknown
	private var gamePolicyCtlInstalled: IsGamePolicyCtlInstalled = .unknown
	private var prefsWindowController: NSWindowController?
	private var statusItem : NSStatusItem!
	
	// MARK: Application delegate
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		let menu = NSMenu()
		
		// Set up the status item:
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		self.statusItem.menu = menu
		self.statusItem.button?.image = NSImage.init(systemSymbolName: "gamecontroller.circle", accessibilityDescription: nil)
		menu.delegate = self
		
		// Enable some default defaults. Add some fairly common apps that could benefit from Game Mode being on:
		UserDefaults.standard.register(defaults: [PrefsViewController.forceGameModeOnKey: true,
												  PrefsViewController.turnGameModeBackToAutomaticKey: true, PrefsViewController.appBundleIDsThatForceOnKey: [
													"com.codeweavers.CrossOver",		// CrossOver
													"com.nvidia.gfnpc.mall",			// GeForce NOW
													"com.heroicgameslauncher.hgl",		// Heroic Games Launcher
													"com.parallels.desktop.appstore",	// Parallels Desktop (App Store version)
													"com.parallels.desktop.console",	// Parallels Desktop (ad-hoc version)
													"com.playstation.RemotePlay",		// PS Remote Play
													"com.libretro.dist.RetroArch",		// RetroArch
													"com.vmware.fusion",				// VMware Fusion
													"com.isaacmarovitz.Whisky"			// Whisky
												  ]])
		
		// Ask the user if we can send them notifications:
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { (granted, error) in
		}
		// Install notifications for when apps are launched and terminated, if gamepolicyctl is installed:
		self.updateStateAndConditionallyInstallNotificationWatchers()
		// Watch for preference changes:
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsChangedNotification), name: UserDefaults.didChangeNotification, object: nil)
		// Also check to see if any currently launched apps should trigger Game Mode. Do this after registering the notification to reduce the chance of an app slipping through due to a race condition.
		self.userDefaultsChangedNotification(nil)
	}
	
	func applicationWillTerminate(_ notification: Notification) {
		// This may or may not be necessary, but let's clean up after ourselves:
		if self.appLaunchedNotificationObserver != nil {
			NotificationCenter.default.removeObserver(self.appLaunchedNotificationObserver!)
		}
		
		if self.appTerminatedNotificationObserver != nil {
			NotificationCenter.default.removeObserver(self.appTerminatedNotificationObserver!)
		}
	}
	
	// MARK: Menu delegate
	
	func menuNeedsUpdate(_ menu: NSMenu) {
		updateStateAndConditionallyInstallNotificationWatchers()
		
		// Build the menu manually based on what running gamepolicyctl tells us:
		menu.removeAllItems()
		
		if self.gamePolicyCtlInstalled == .unknown {
			menu.addItem(withTitle: NSLocalizedString("MenuCantCheckStatus1", comment: ""), action: nil, keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuCantCheckStatus2", comment: ""), action: nil, keyEquivalent: "")
			menu.addItem(NSMenuItem.separator())
		}
		if self.gamePolicyCtlInstalled == .notInstalled {
			menu.addItem(withTitle: NSLocalizedString("MenuNoXcode1", comment: ""), action: nil, keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuNoXcode2", comment: ""), action: nil, keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuDownloadXcode", comment: ""), action: #selector(downloadXcodeAction), keyEquivalent: "")
			menu.addItem(NSMenuItem.separator())
		} else {
			switch (self.enablementPolicy) {
			case .automatic:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyAutomatic", comment: ""), action: nil, keyEquivalent: "")
			case .unknown:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyUnknown", comment: ""), action: nil, keyEquivalent: "")
			case .disabled:
				if UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeOffKey) {
					menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyForcedOff", comment: ""), action: nil, keyEquivalent: "")
				} else if self.appsThatEnableGameMode.count > 0 {
					menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyForcedOn", comment: ""), action: nil, keyEquivalent: "")
					menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyForcedOnApps", comment: ""), action: nil, keyEquivalent: "")
					for app in self.appsThatEnableGameMode {
						menu.addItem(withTitle: "\t\(app.localizedName ?? app.executableURL?.lastPathComponent ?? NSLocalizedString("MenuGameModeEnablementPolicyUnknownApp", comment: ""))", action: nil, keyEquivalent: "")
					}
				} else {
					menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyManual", comment: ""), action: nil, keyEquivalent: "")
				}
			}
			
			switch (self.gameMode) {
			case .unknown:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeUnknown", comment: ""), action: nil, keyEquivalent: "")
			case .enabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeOn", comment: ""), action: nil, keyEquivalent: "")
			case .temporarilyEnabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeTemporarilyOn", comment: ""), action: nil, keyEquivalent: "")
			case .disabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeOff", comment: ""), action: nil, keyEquivalent: "")
			}
			
			menu.addItem(NSMenuItem.separator())
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceAutomatic", comment: ""), action: #selector(automaticallyEnableGameModeAction), keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceOn", comment: ""), action: #selector(enableGameModeAction), keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceOff", comment: ""), action: #selector(disableGameModeAction), keyEquivalent: "")
			menu.addItem(NSMenuItem.separator())
			menu.addItem(withTitle: NSLocalizedString("MenuPrefs", comment: ""), action: #selector(openPreferences), keyEquivalent: "")
			menu.addItem(NSMenuItem.separator())
		}
		menu.addItem(withTitle: NSLocalizedString("MenuQuit", comment: ""), action: #selector(NSApplication.terminate), keyEquivalent: "")
	}
	
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(automaticallyEnableGameModeAction) {
			menuItem.state = self.enablementPolicy == .automatic ? .on : .off
		}
		if menuItem.action == #selector(enableGameModeAction) {
			menuItem.state = self.enablementPolicy == .disabled && self.gameMode == .enabled ? .on : .off
		}
		if menuItem.action == #selector(disableGameModeAction) {
			menuItem.state = self.enablementPolicy == .disabled && self.gameMode == .disabled ? .on : .off
		}
		return true
	}
	
	// MARK: Actions
	
	@objc func automaticallyEnableGameModeAction(_ sender: Any?) {
		self.automaticallyEnableGameMode()
		self.appsThatEnableGameMode.removeAll()	// because the user forced an action, reset this set
	}
	
	@objc func disableGameModeAction(_ sender: Any?) {
		self.disableGameMode()
		self.appsThatEnableGameMode.removeAll()
	}
	
	@objc func downloadXcodeAction(_ sender: Any) {
		let url = URL(string: "https://apps.apple.com/us/app/xcode/id497799835?mt=12")!
		
		NSWorkspace.shared.open(url)
	}
	
	@objc func enableGameModeAction(_ sender: Any?) {
		self.enableGameMode()
	}
	
	@objc func openPreferences(_ sender: Any) {
		if self.prefsWindowController == nil {
			self.prefsWindowController = NSStoryboard.main?.instantiateController(withIdentifier: "PreferencesWindow") as? NSWindowController
		}
		
		NSApplication.shared.activate(ignoringOtherApps: true)
		if !(self.prefsWindowController?.window?.isVisible ?? false) {
			self.prefsWindowController?.window!.center()
			self.prefsWindowController?.window!.makeKeyAndOrderFront(sender)
		} else if self.prefsWindowController?.window != nil {
			self.prefsWindowController?.window!.makeKeyAndOrderFront(sender)
		}
	}
	
	// MARK: Notifications
	
	@objc func userDefaultsChangedNotification(_ notification: Notification?) {
		// Sanity check: if there turns out to be some bug in the app where the user somehow turned both force-on and force-off at once, or if the user screwed around with the user defaults behind the app's back, then we override this with force-on.
		if UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeOnKey) && UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeOffKey) {
			NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)
			UserDefaults.standard.set(false, forKey: PrefsViewController.forceGameModeOffKey)
			NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsChangedNotification), name: UserDefaults.didChangeNotification, object: nil)
		}
		
		// Conditionally force Game Mode off if the user willed it:
		if UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeOffKey) {
			self.disableGameMode()
		} else if UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeOnKey) {
			// If Game Mode was forced off, then put it back on automatic:
			if self.enablementPolicy == .disabled && self.gameMode == .disabled {
				self.automaticallyEnableGameMode()
			}
			
			let enabledBundleIDs = UserDefaults.standard.stringArray(forKey: PrefsViewController.appBundleIDsThatForceOnKey) ?? []
			
			// Check to see if the user removed an app that forced Game Mode on previously. If they did, then we should see if we should take it back to automatic:
			for appThatEnabledGameMode in self.appsThatEnableGameMode {
				if let bundleIdentifier = appThatEnabledGameMode.bundleIdentifier {
					if !enabledBundleIDs.contains(bundleIdentifier) {
						self.checkIfTerminatedApplicationShouldRevertToAutomaticGameMode(terminatedApp: appThatEnabledGameMode)
					}
				}
			}
			
			// Check to see if any currently launched apps should trigger Game Mode. Do this after registering the notification to reduce the chance of an app slipping through due to a race condition.
			for runningApp in NSWorkspace.shared.runningApplications {
				self.checkIfRunningApplicationShouldForceOnGameMode(runningApp: runningApp)
			}
		} else {
			// If both are off, then go back to Automatic as needed:
			if self.enablementPolicy == .disabled {
				self.automaticallyEnableGameMode()
			}
			self.appsThatEnableGameMode.removeAll()
		}
	}
	
	// MARK: Internal
	
	private func automaticallyEnableGameMode() {
		if self.setGameModeEnablementPolicyString("auto") {
			self.enablementPolicy = .automatic
			self.gameMode = .disabled	// we actually don't know if the OS will turn it on or off immediately, but we need to assume it's off, or the next attempt to turn it on when an app is launched will fail
		}
	}
	
	private func checkIfRunningApplicationShouldForceOnGameMode(runningApp: NSRunningApplication!) {
		if UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeOnKey) {	// is Force Game Mode On enabled?
			if let appBundleIDsThatForceOn = UserDefaults.standard.array(forKey: PrefsViewController.appBundleIDsThatForceOnKey) as? [String] {	// and we have app bundle IDs that will trigger game mode on if launched?
				if let bundleID = runningApp.bundleIdentifier {
					if appBundleIDsThatForceOn.contains(bundleID) {	// and this is one of those apps?
						if self.gameMode != .enabled {	// if it's not enabled, let's enable it and tell the user we enabled it
							let notificationContent = UNMutableNotificationContent()
							
							notificationContent.title = NSLocalizedString("GameModeForcedOnTitle", comment: "")
							notificationContent.body = String(format: NSLocalizedString("GameModeForcedOnSubtitle", comment: ""), runningApp.localizedName ?? "?")
							
							let notification = UNNotificationRequest(identifier: "GameModeOn", content: notificationContent, trigger: nil)
							
							UNUserNotificationCenter.current().add(notification)
							self.enableGameMode()
						}
						self.appsThatEnableGameMode.insert(runningApp)
					}
				}
			}
		}
	}
	
	private func checkIfTerminatedApplicationShouldRevertToAutomaticGameMode(terminatedApp: NSRunningApplication!) {
		if self.appsThatEnableGameMode.contains(terminatedApp) {	// and we previously forced game mode on because this app launched?
			self.appsThatEnableGameMode.remove(terminatedApp)
			if self.appsThatEnableGameMode.isEmpty && UserDefaults.standard.bool(forKey: PrefsViewController.turnGameModeBackToAutomaticKey) {	// if that was the last app launched that forced game mode on, and the user set the preference to switch it back to automatic, then let's do that
				let notificationContent = UNMutableNotificationContent()
				
				notificationContent.title = NSLocalizedString("GameModeForcedAutomaticTitle", comment: "")
				notificationContent.body = String(format: NSLocalizedString("GameModeForcedAutomaticSubtitle", comment: ""), terminatedApp.localizedName ?? "?")
				
				let notification = UNNotificationRequest(identifier: "GameModeOff", content: notificationContent, trigger: nil)
				
				UNUserNotificationCenter.current().add(notification)
				self.automaticallyEnableGameMode()
			}
		}
	}
	
	private func disableGameMode() {
		if self.setGameModeEnablementPolicyString("off") {
			self.enablementPolicy = .disabled
			self.gameMode = .disabled
		}
	}
	
	private func enableGameMode() {
		if setGameModeEnablementPolicyString("on") {
			self.enablementPolicy = .disabled
			self.gameMode = .enabled
		}
	}
	
	private func gamePolicyCtlStatus() -> (isInstalled: IsGamePolicyCtlInstalled, gameMode: IsGameModeEnabled, enablementPolicy: GameModeEnablementPolicy) {
		let process = Process()
		let pipe = Pipe()
		let fileHandle = pipe.fileHandleForReading
		
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["gamepolicyctl", "game-mode", "status"]
		process.standardOutput = pipe
		process.standardError = pipe
		process.launch()
		process.waitUntilExit()
		
		let output: Data?
		
		do {
			output = try fileHandle.readToEnd()
		} catch {
			Logger().error("Failed to read output from gamepolicyctl due to an error: \(error)")
			return (.unknown, .unknown, .unknown)
		}
		guard let outputString = String(data: output ?? Data(), encoding: .utf8) else {
			Logger().error("Failed to read output from gamepolicyctl; the output could not be read as valid UTF-8.")
			return (.unknown, .unknown, .unknown)
		}
		var gameMode: IsGameModeEnabled = .unknown
		var enablementPolicy: GameModeEnablementPolicy = .unknown
		
		if outputString.contains("xcrun: error: unable to find utility") {	// unable to find - not installed
			return (.notInstalled, .unknown, .unknown)
		}
		
		// gamepolicyctl uses an escape sequence to add color to the text. We don't care about the color, so use regular expression matching in order to ignore the color escape sequence using (.+).
		do {
			if outputString.contains(try Regex("Game mode is(.+)on(.+)Game mode will soon turn off")) {
				gameMode = .temporarilyEnabled
			} else if outputString.contains(try Regex("Game mode is(.+)on")) {
				gameMode = .enabled
			} else if outputString.contains(try Regex("Game mode is(.+)off")) {
				gameMode = .disabled
			}
		} catch {
			gameMode = .disabled
		}
		
		if outputString.contains("Game mode enablement policy is currently automatic") {
			enablementPolicy = .automatic
		} else if outputString.contains("Game mode enablement policy is currently disabled") {
			enablementPolicy = .disabled
		}
		return (.installed, gameMode, enablementPolicy)
	}
	
	private func setGameModeEnablementPolicyString(_ policyString: String!) -> Bool {
		let process = Process()
		let pipe = Pipe()
		let fileHandle = pipe.fileHandleForReading
		
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["gamepolicyctl", "game-mode", "set", policyString]
		process.standardOutput = pipe
		process.standardError = pipe
		process.launch()
		process.waitUntilExit()
		
		let output: Data?
		
		do {
			output = try fileHandle.readToEnd()
		} catch {
			output = nil
		}
		guard let outputString = String(data: output ?? Data(), encoding: .utf8) else {
			return false
		}
		return outputString.contains(policyString)
	}
	
	private func updateStateAndConditionallyInstallNotificationWatchers() {
		let status = gamePolicyCtlStatus()
		
		if (status.isInstalled == .installed) {
			weak var weakSelf = self
			
			if appLaunchedNotificationObserver == nil {
				self.appLaunchedNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { aNotification in
					if let runningApp = aNotification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {	// sanity check - this is an NSRunningApplication, right?
						if let strongSelf = weakSelf {
							strongSelf.checkIfRunningApplicationShouldForceOnGameMode(runningApp: runningApp)
						}
					} else {
						Logger().error("Error! NSWorkspace.applicationUserInfoKey was not an NSRunningApplication for some reason.")
					}
				}
			}
			
			if appTerminatedNotificationObserver == nil {
				self.appTerminatedNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { aNotification in
					if let terminatedApp = aNotification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {	// sanity check - this is an NSRunningApplication, right?
						if let strongSelf = weakSelf {
							strongSelf.checkIfTerminatedApplicationShouldRevertToAutomaticGameMode(terminatedApp: terminatedApp)
						}
					} else {
						Logger().error("Error! NSWorkspace.applicationUserInfoKey was not an NSRunningApplication for some reason.")
					}
				}
			}
		} else {	// if it's not installed, but the notifications are on, then remove them
			if self.appLaunchedNotificationObserver != nil {
				NSWorkspace.shared.notificationCenter.removeObserver(self.appLaunchedNotificationObserver as Any)
				self.appLaunchedNotificationObserver = nil
			}
			
			if self.appTerminatedNotificationObserver != nil {
				NSWorkspace.shared.notificationCenter.removeObserver(self.appTerminatedNotificationObserver as Any)
				self.appTerminatedNotificationObserver = nil
			}
		}
		self.gamePolicyCtlInstalled = status.isInstalled
		self.gameMode = status.gameMode
		self.enablementPolicy = status.enablementPolicy
	}
}

