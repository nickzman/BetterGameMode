//
//  PrefsViewController.swift
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
import ServiceManagement

class PrefsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	public static let appBundleIDsThatForceOnKey = "AppBundleIDsThatForceOn"
	public static let forceGameModeOffKey = "ForceGameModeOff"
	public static let forceGameModeOnKey = "ForceGameModeOn"
	public static let turnGameModeBackToAutomaticKey = "TurnGameModeBackToAutomatic"
	
	@IBOutlet weak var addApplicationButton: NSButton!
	@IBOutlet weak var appsThatForceOnTableView: NSTableView!
	@IBOutlet weak var forceGameModeOffCheckbox: NSButton!
	@IBOutlet weak var forceGameModeOnCheckbox: NSButton!
	@IBOutlet weak var launchOnLoginCheckbox: NSButton!
	@IBOutlet weak var removeApplicationButton: NSButton!
	@IBOutlet weak var turnGameModeBackToAutomaticCheckbox: NSButton!
	@IBOutlet weak var versionLabel: NSTextField!
	
	private var appBundleIDsThatForceOn: [String] = []
	
	override func viewDidLoad() {
		let launchOnLoginStatus = SMAppService.mainApp.status
		
		super.viewDidLoad()
		
		self.versionLabel.stringValue = String(format: NSLocalizedString("Version", comment: ""), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
		
		// Update the UI to reflect the user defaults:
		self.launchOnLoginCheckbox.state = launchOnLoginStatus == .enabled ? .on : .off
		self.forceGameModeOnCheckbox.state = UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeOnKey) ? .on : .off
		self.turnGameModeBackToAutomaticCheckbox.state = UserDefaults.standard.bool(forKey: PrefsViewController.turnGameModeBackToAutomaticKey) ? .on : .off
		self.forceGameModeOffCheckbox.state = UserDefaults.standard.bool(forKey: PrefsViewController.forceGameModeOffKey) ? .on : .off
		self.appBundleIDsThatForceOn = UserDefaults.standard.array(forKey: PrefsViewController.appBundleIDsThatForceOnKey) as? [String] ?? []
		self.appsThatForceOnTableView.reloadData()
		
		// Disable controls for preferences that don't do anything if force gaming mode isn't on:
		self.forceGameModeOnCheckbox.isEnabled = self.forceGameModeOffCheckbox.state == .off
		self.turnGameModeBackToAutomaticCheckbox.isEnabled = self.forceGameModeOnCheckbox.state == .on
		self.forceGameModeOffCheckbox.isEnabled = self.forceGameModeOnCheckbox.state == .off
		self.appsThatForceOnTableView.isEnabled = self.forceGameModeOnCheckbox.state == .on
		self.addApplicationButton.isEnabled = self.forceGameModeOnCheckbox.state == .on
	}
	
	// MARK: Table view data source
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return self.appBundleIDsThatForceOn.count
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let cell = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as! NSTableCellView
		let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: self.appBundleIDsThatForceOn[row])
		
		if appURL != nil {	// is the app installed, according to Launch Services?
			let bundle = Bundle(url: appURL!)
			
			cell.imageView?.image = NSWorkspace.shared.icon(forFile: appURL!.path)
			if bundle != nil {
				cell.textField?.stringValue = (bundle!.localizedInfoDictionary?[String(kCFBundleNameKey)] as? String ?? "")
			}
			cell.textField?.stringValue = appURL!.lastPathComponent
		} else {	// if not, then just print the bundle ID so the user can at least delete it
			cell.imageView?.image = nil
			cell.textField?.stringValue = "(\(self.appBundleIDsThatForceOn[row]))"
		}
		return cell
	}
	
	// MARK: Table view delegate
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		self.removeApplicationButton.isEnabled = self.appsThatForceOnTableView.selectedRowIndexes.count > 0	// the remove button needs something selected for it to work
	}
	
	// MARK: Actions
	
	@IBAction func addApplicationAction(_ sender: Any) {
		let openPanel = NSOpenPanel()
		
		openPanel.allowsMultipleSelection = false
		openPanel.allowedContentTypes = [.application]
		openPanel.beginSheetModal(for: self.view.window!) { result in
			if result == .OK {
				let appURL = openPanel.url!
				if let appBundle = Bundle(url: appURL) {	// we need to load the app's bundle identifier
					if let appBundleIdentifier = appBundle.bundleIdentifier {
						self.appBundleIDsThatForceOn.append(appBundleIdentifier)
						self.appsThatForceOnTableView.insertRows(at: IndexSet(integer: self.appBundleIDsThatForceOn.count - 1), withAnimation: .effectFade)
						UserDefaults.standard.set(self.appBundleIDsThatForceOn, forKey: PrefsViewController.appBundleIDsThatForceOnKey)
					}
				}
			}
		}
	}
	
	// MARK: Actions
	
	@IBAction func forceGameModeOffAction(_ sender: Any) {
		if self.forceGameModeOffCheckbox.state == .on {
			UserDefaults.standard.set(true, forKey: PrefsViewController.forceGameModeOffKey)
			self.forceGameModeOnCheckbox.isEnabled = false
			self.turnGameModeBackToAutomaticCheckbox.isEnabled = false
			self.appsThatForceOnTableView.isEnabled = false
			self.addApplicationButton.isEnabled = false
		} else {
			UserDefaults.standard.set(false, forKey: PrefsViewController.forceGameModeOffKey)
			self.forceGameModeOnCheckbox.isEnabled = true
			self.turnGameModeBackToAutomaticCheckbox.isEnabled = true
			self.appsThatForceOnTableView.isEnabled = true
			self.addApplicationButton.isEnabled = true
		}
	}
	
	@IBAction func forceGameModeOnAction(_ sender: Any) {
		if self.forceGameModeOnCheckbox.state == .on {
			UserDefaults.standard.set(true, forKey: PrefsViewController.forceGameModeOnKey)
			self.turnGameModeBackToAutomaticCheckbox.isEnabled = true
			self.forceGameModeOffCheckbox.isEnabled = false
			self.appsThatForceOnTableView.isEnabled = true
			self.addApplicationButton.isEnabled = true
			self.removeApplicationButton.isEnabled = self.appsThatForceOnTableView.selectedRow >= 0
		} else {	// disable all controls for things that don't do anything if this setting is disabled
			UserDefaults.standard.set(false, forKey: PrefsViewController.forceGameModeOnKey)
			self.turnGameModeBackToAutomaticCheckbox.isEnabled = false
			self.forceGameModeOffCheckbox.isEnabled = true
			self.appsThatForceOnTableView.isEnabled = false
			self.addApplicationButton.isEnabled = false
			self.removeApplicationButton.isEnabled = false
		}
	}
	
	@IBAction func launchOnLoginAction(_ sender: Any) {
		if self.launchOnLoginCheckbox.state == .on {
			do {
				try SMAppService.mainApp.register()
			} catch {
				Logger().error("Error registering app: \(error)")
			}
		} else {
			do {
				try SMAppService.mainApp.unregister()
			} catch {
				Logger().error("Error unregistering app: \(error)")
			}
		}
	}
	
	@IBAction func removeApplicationAction(_ sender: Any) {
		let selectedRow = self.appsThatForceOnTableView.selectedRow
		
		if selectedRow >= 0 {	// sanity check: don't crash if nothing is selected
			self.appBundleIDsThatForceOn.remove(at: selectedRow)
			self.appsThatForceOnTableView.removeRows(at: IndexSet(integer: selectedRow), withAnimation: .effectFade)
			UserDefaults.standard.set(self.appBundleIDsThatForceOn, forKey: PrefsViewController.appBundleIDsThatForceOnKey)
		}
	}
	
	@IBAction func turnGameModeBackToAutomaticAction(_ sender: Any) {
		UserDefaults.standard.set(self.turnGameModeBackToAutomaticCheckbox.state == .on ? true : false, forKey: PrefsViewController.turnGameModeBackToAutomaticKey)
	}
}

