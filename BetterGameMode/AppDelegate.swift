//
//  AppDelegate.swift
//  BetterGameMode
//
//  Created by Nick Zitzmann on 12/27/24.
//

import Cocoa
import os.log

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
	private enum IsGamePolicyCtlInstalled: Int {
		case unknown
		case notInstalled
		case installed
	}
	private enum GameModeEnablementPolicy: Int {
		case unknown
		case automatic
		case disabled
	}
	private enum IsGameModeEnabled: Int {
		case unknown
		case disabled
		case enabled
	}
	private var appLaunchedNotificationObserver: NSObjectProtocol?
	private var appTerminatedNotificationObserver: NSObjectProtocol?
	
	private var appsThatEnableGameMode: Set<NSRunningApplication> = []
	private var enablementPolicy: GameModeEnablementPolicy = .unknown
	private var gameMode: IsGameModeEnabled = .unknown
	private var gamePolicyCtlInstalled: IsGamePolicyCtlInstalled = .unknown
	private var prefsWindowController: NSWindowController?
	private var statusItem : NSStatusItem!
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		let menu = NSMenu()
		weak var weakSelf = self
		
		// Set up the status item:
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		self.statusItem.menu = menu
		self.statusItem.button?.image = NSImage.init(systemSymbolName: "gamecontroller.circle", accessibilityDescription: nil)
		menu.delegate = self
		
		self.appLaunchedNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { aNotification in
			if UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeKey) {
				if let runningApp = aNotification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
					if let appBundleIDsThatForceOn = UserDefaults.standard.array(forKey: PrefsViewController.appBundleIDsThatForceOnKey) as? [String] {
						if appBundleIDsThatForceOn.contains(runningApp.bundleIdentifier!) {
							if let strongSelf = weakSelf {
								strongSelf.setGameModeEnablementPolicyString("on")
								strongSelf.appsThatEnableGameMode.insert(runningApp)
							}
						}
					}
				}
			}
		}
		self.appTerminatedNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { aNotification in
			if let terminatedApp = aNotification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
				if let strongSelf = weakSelf {
					if strongSelf.appsThatEnableGameMode.contains(terminatedApp) {
						strongSelf.appsThatEnableGameMode.remove(terminatedApp)
						if UserDefaults.standard.bool(forKey: PrefsViewController.turnGameModeBackToAutomaticKey) {
							if strongSelf.appsThatEnableGameMode.isEmpty {
								strongSelf.setGameModeEnablementPolicyString("auto")
							}
						}
					}
				}
			}
		}
	}
	
	func menuNeedsUpdate(_ menu: NSMenu) {
		let status = gamePolicyCtlStatus()
		
		self.gamePolicyCtlInstalled = status.isInstalled
		self.gameMode = status.gameMode
		self.enablementPolicy = status.enablementPolicy
		
		// Build the menu manually based on what running gamepolicyctl tells us:
		menu.removeAllItems()
		
		if status.isInstalled == .unknown {
			menu.addItem(withTitle: NSLocalizedString("MenuCantCheckStatus1", comment: ""), action: nil, keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuCantCheckStatus2", comment: ""), action: nil, keyEquivalent: "")
		}
		if status.isInstalled == .notInstalled {
			menu.addItem(withTitle: NSLocalizedString("MenuNoXcode1", comment: ""), action: nil, keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuNoXcode2", comment: ""), action: nil, keyEquivalent: "")
		} else {
			switch (status.enablementPolicy) {
			case .automatic:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyAutomatic", comment: ""), action: nil, keyEquivalent: "")
			case .unknown:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyUnknown", comment: ""), action: nil, keyEquivalent: "")
			case .disabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeEnablementPolicyManual", comment: ""), action: nil, keyEquivalent: "")
			}
			
			switch (status.gameMode) {
			case .unknown:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeUnknown", comment: ""), action: nil, keyEquivalent: "")
			case .enabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeOn", comment: ""), action: nil, keyEquivalent: "")
			case .disabled:
				menu.addItem(withTitle: NSLocalizedString("MenuGameModeOff", comment: ""), action: nil, keyEquivalent: "")
			}
			
			menu.addItem(NSMenuItem.separator())
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceAutomatic", comment: ""), action: #selector(automaticallyEnableGameMode), keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceOn", comment: ""), action: #selector(enableGameMode), keyEquivalent: "")
			menu.addItem(withTitle: NSLocalizedString("MenuGameModeForceOff", comment: ""), action: #selector(disableGameMode), keyEquivalent: "")
			menu.addItem(NSMenuItem.separator())
		}
		menu.addItem(withTitle: NSLocalizedString("MenuPrefs", comment: ""), action: #selector(openPreferences), keyEquivalent: "")
		menu.addItem(NSMenuItem.separator())
		menu.addItem(withTitle: NSLocalizedString("MenuQuit", comment: ""), action: #selector(quit), keyEquivalent: "")
	}
	
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(automaticallyEnableGameMode) {
			menuItem.state = self.enablementPolicy == .automatic ? .on : .off
		}
		if menuItem.action == #selector(enableGameMode) {
			menuItem.state = self.enablementPolicy == .disabled && self.gameMode == .enabled ? .on : .off
		}
		if menuItem.action == #selector(disableGameMode) {
			menuItem.state = self.enablementPolicy == .disabled && self.gameMode == .disabled ? .on : .off
		}
		return true
	}
	
	private func setGameModeEnablementPolicyString(_ policyString: String!) {
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
			return
		}
	}
	
	@objc func automaticallyEnableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("auto")
	}
	
	@objc func disableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("off")
	}
	
	@objc func enableGameMode(_ sender: Any) {
		setGameModeEnablementPolicyString("on")
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
	
	@objc func quit(_ sender: Any) {
		NSApplication.shared.terminate(sender)
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
			return (.unknown, .unknown, .unknown)
		}
		var gameMode: IsGameModeEnabled = .unknown
		var enablementPolicy: GameModeEnablementPolicy = .unknown
		
		if outputString.contains("xcrun: error: unable to find utility") {	// unable to find - not installed
			return (.notInstalled, .unknown, .unknown)
		}
		
		do {
			if outputString.contains(try Regex("Game mode is(.+)off")) {
				gameMode = .disabled
			} else if outputString.contains(try Regex("Game mode is(.+)on")) {
				gameMode = .enabled
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
}

