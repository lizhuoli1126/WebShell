//
//  ViewController.swift
//  WebShell
//
//  Created by Randy on 15/12/19.
//  Copyright © 2015 RandyLu. All rights reserved.
//
//  Wesley de Groot (@wdg), Added Notification and console.log Support

import Cocoa
import WebKit
import Foundation
import AppKit
import AudioToolbox
import IOKit.ps

class ViewController: NSViewController, WebFrameLoadDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    
    private var mainWebview: WKWebView!
    @IBOutlet var mainWindow: NSView!
    @IBOutlet weak var loadingBar: NSProgressIndicator!
    @IBOutlet weak var launchingLabel: NSTextField!
    
    // TODO: configure your app here
    let SETTINGS: [String: Any]  = [
        
        // Url to browse to.
        "url": "https://www.google.com",
        
        "title": NSBundle.mainBundle().infoDictionary!["CFBundleName"] as! String,
        
        // Do you want to use the document title?
        "useDocumentTitle": true,
        
        // Multilanguage loading text!
        "launchingText": NSLocalizedString("Launching...",comment:"Launching..."),

        // Note that the window min height is 640 and min width is 1000 by default. You could change it in Main.storyboard
        "initialWindowHeight": 640,
        "initialWindowWidth": 1000,
        
        // Open target=_blank in a new screen?
        "openInNewScreen": false,
        
        // Do you want a loading bar?
        "showLoadingBar": true,
        
        "consoleSupport": true
    ]
    
    func webView(sender: WebView!, runJavaScriptAlertPanelWithMessage message: String!, initiatedByFrame frame: WebFrame!) {
        // You could custom the JavaScript alert behavior here
        let alert = NSAlert.init()
        alert.addButtonWithTitle("OK") // message box button text
        alert.messageText = "Message" // message box title
        alert.informativeText = message
        alert.runModal()
    }

    var firstLoadingStarted = false
    var firstAppear = true
    
    override func loadView() {
        super.loadView()
        // init webview

        self.mainWebview = WKWebView()
        mainWebview.navigationDelegate = self
        self.view = self.mainWebview!
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addObservers()
        initSettings()
    }
    
    override func viewWillAppear() {
        if(firstAppear){
            initWindow()
            goHome()
        }
    }
    
    func addObservers(){
        // add menu action observers
        let observers = ["goHome", "reload", "copyUrl", "clearNotificationCount"]
        
        for observer in observers{
            NSNotificationCenter.defaultCenter().addObserver(self, selector: NSSelectorFromString(observer), name: observer, object: nil)
        }
    }
    
    func goHome(){
        let homeUrl = NSURL(string: SETTINGS["url"] as! String)
        loadUrl(homeUrl!)
    }
    
    func reload(){
        let currentUrl = mainWebview.URL
        loadUrl(currentUrl!)
    }
    
    func copyUrl(){
        let currentUrl = mainWebview.URL
        let clipboard: NSPasteboard = NSPasteboard.generalPasteboard()
        clipboard.clearContents()
        
        clipboard.setString(currentUrl?.absoluteString ?? "about:blank", forType: NSStringPboardType)
    }
    
    func initSettings(){
        // controll the progress bar
        if(!(SETTINGS["showLoadingBar"] as? Bool)!){
            loadingBar.hidden = true
        }
        
        // set launching text
        launchingLabel.stringValue = (SETTINGS["launchingText"] as? String)!
    }
    
    func initWindow(){
        
        firstAppear = false
        
        // set window size
        var frame: NSRect = mainWindow.frame
        
        let WIDTH: CGFloat = CGFloat(SETTINGS["initialWindowWidth"] as! Int),
            HEIGHT: CGFloat = CGFloat(SETTINGS["initialWindowHeight"] as! Int)
        
        frame.size.width = WIDTH
        frame.size.height = HEIGHT
        
        // @wdg Fixed screen position (now it centers)
        // Issue: #19
        // Note: do not use HEIGHT, WIDTH for some strange reason the window will be positioned 25px from bottom!
        let ScreenHeight:CGFloat = (NSScreen.mainScreen()?.frame.size.width)!,
            WindowHeight:CGFloat = CGFloat(SETTINGS["initialWindowWidth"] as! Int), // do not use HEIGHT!
            ScreenWidth:CGFloat  = (NSScreen.mainScreen()?.frame.size.height)!,
            WindowWidth:CGFloat  = CGFloat(SETTINGS["initialWindowHeight"] as! Int) // do not use WIDTH!
        frame.origin.x = (ScreenHeight/2 - WindowHeight/2)
        frame.origin.y = (ScreenWidth/2  - WindowWidth/2)
        
        // @froge-xyz Fixed initial window size
        // Issue: #1
        mainWindow.window?.setFrame(frame, display: true)
        
        // set window title
        mainWindow.window?.title = SETTINGS["title"] as! String
        
        // Force some preferences before loading...
        let config = mainWebview.configuration
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.plugInsEnabled = true
    }
    
    func loadUrl(url: NSURL){
        loadingBar.stopAnimation(self)
        
        mainWebview.loadRequest(NSURLRequest(URL: url))
        
        // Inject Webhooks
        injectWebhooks()
    }
    
    
    // webview settings
    func webView(sender: WebView!, didStartProvisionalLoadForFrame frame: WebFrame!) {
        loadingBar.startAnimation(self)
        
        if(!firstLoadingStarted){
            firstLoadingStarted = true
            launchingLabel.hidden = false
        }
    }
    
    // webview JavaScript message handler
    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        print("message: \(message.name) \n content: \(message.body)")
        switch message.name {
        case "notification":
            let json = JSON(message.body)
            let title = json["title"].string ?? "undefined"
            let body = json["body"].string ?? "undefined"
            let iconUrl = json["icon"].string ?? "undefined"
            makeNotification(title, message: body, iconUrl: iconUrl)
        case "battery":
            let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
            let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue()
            if (CFArrayGetCount(sources) == 0) {
                return	// Could not retrieve battery information. System may not have a battery.
            } else {
                let batterySource = CFArrayGetValueAtIndex(sources, 0) as! AnyObject
                let pSource = IOPSGetPowerSourceDescription(blob, batterySource).takeUnretainedValue()
                
                let batteryDic:NSDictionary = pSource
                
                let isCharge = batteryDic.objectForKey(kIOPSIsChargingKey) as! Int // 1 for charging, 0 for not
                let curCapacity = batteryDic.objectForKey(kIOPSCurrentCapacityKey) as! Int // current capacity
                let maxCapacity = batteryDic.objectForKey(kIOPSMaxCapacityKey) as! Int // max capacity
                let timeToEmpty = batteryDic.objectForKey(kIOPSTimeToEmptyKey) as! Int // time to empty(not charging)
                let timeToFull = batteryDic.objectForKey(kIOPSTimeToFullChargeKey) as! Int // time to full(charging)
                let level = curCapacity / maxCapacity // current level
                
                evaluateScript("navigator.battery={charging: \(Bool(isCharge)), timeToEmpty: \(timeToEmpty), timeToFull: \(timeToFull), level: \(level)")
            }
        case "openExternal":
            let url = message.body as! String
            NSWorkspace.sharedWorkspace().openURL(NSURL(string: (url))!)
        case "open":
            let url = message.body as! String
            self.loadUrl(NSURL(string: url)!)
        case "console":
            print(message.body)
        default: break
        }
    }
    
    func webView(sender: WebView!, didFinishLoadForFrame frame: WebFrame!) {
        loadingBar.stopAnimation(self)
        
        if(!launchingLabel.hidden){
            launchingLabel.hidden = true
        }

        // Inject Webhooks
        self.injectWebhooks()
    }
    
    // @wdg: Enable file uploads.
    // Issue: #29
    func webView(sender: WebView!, runOpenPanelForFileButtonWithResultListener resultListener: WebOpenPanelResultListener!, allowMultipleFiles: Bool) {
        // Init panel with options
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowMultipleFiles
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        
        // On clicked on ok then...
        panel.beginWithCompletionHandler { (result) -> Void in
            // User clicked OK
            if result == NSFileHandlingPanelOKButton {
                
                // make the upload qeue named 'uploadQeue'
                let uploadQeue:NSMutableArray = NSMutableArray()
                for (var i=0; i<panel.URLs.count; i++)
                {
                    // Add to upload qeue, needing relativePath.
                    uploadQeue.addObject(panel.URLs[i].relativePath!)
                }
            
                if (panel.URLs.count == 1) {
                    // One file
                    resultListener.chooseFilename(String(uploadQeue[0]))
                } else {
                    // Multiple files
                    resultListener.chooseFilenames(uploadQeue as [AnyObject])
                }
            }
        }

    }
    
    func webView(sender: WebView!, didReceiveTitle title: String!, forFrame frame: WebFrame!) {
        if(SETTINGS["useDocumentTitle"] as! Bool){
            mainWindow.window?.title = title
        }
    }
    
    func injectWebhooks() {
        // @wdg Hack URL's if settings is set.
        // Issue: #5
        // Injecting JavaScript (via JavaScriptCore)
        
        if((SETTINGS["openInNewScreen"] as? Bool) != false){
            // _blank to external
            // JavaScript -> Select all <a href='...' target='_blank'>
            evaluateScript("var links=document.querySelectorAll('a');for(var i=0;i<links.length;i++){if(links[i].target==='_blank'){links[i].addEventListener('click',function () {app.openExternal(this.href);})}}")
        } else {
            // _blank to internal
            // JavaScript -> Select all <a href='...' target='_blank'>
            evaluateScript("var links=document.querySelectorAll('a');for(var i=0;i<links.length;i++){if(links[i].target==='_blank'){links[i].addEventListener('click',function () {app.openInternal(this.href);})}}")
        }
        
        // @wdg Add Notification Support
        // Issue: #2
        evaluateScript("function _Notification(title,options){var body=options['body'];var icon=options['icon'];window.webkit.messageHandlers.notification.postMessage({title:title,body:body,icon:icon})}_Notification.length=1;_Notification.permission='granted';_Notification.requestPermission=function(callback){if(typeof callback==='function'){callback(_Notification.permission);return}};window.Notification=_Notification;")
        
        // Add console.log ;)
        // Add Console.log (and console.error, and console.warn)
        if(SETTINGS["consoleSupport"] as! Bool){
            evaluateScript("var console={log:function(){var message='';for(var i=0;i<arguments.length;i++){message+=arguments[i]+' '};window.webkit.messageHandlers.notification.postMessage(message)},warn:function(){var message='';for(var i=0;i<arguments.length;i++){message+=arguments[i]+' '};window.webkit.messageHandlers.notification.postMessage(message)},error:function(){var message='';for(var i=0;i<arguments.length;i++){message+=arguments[i]+' '};window.webkit.messageHandlers.notification.postMessage(message)}};")
        }
        
        // @wdg Add support for target=_blank
        // Issue: #5
        // Fake window.app Library.
        evaluateScript("var app={openExternal:function(url){window.webkit.messageHandlers.openExternal.postMessage(url)},openInternal:function(url){window.webkit.messageHandlers.openInternal.postMessage(url)}}")
        
        // Add Battery!
        evaluateScript("navigator.battery = {charging: true, chargingTime:0, dischargingTime:999, level:1, addEventListener:function(val, cal){}}")
        evaluateScript("navigator.battery={}navigator.getBattery = function() { return {charging: true, chargingTime:0, dischargingTime:999, level:1, addEventListener:function(val, cal){}, then:function(call){return call(navigator.battery)}}}")
    }
    
    
    var notificationCount = 0
    
    func clearNotificationCount(){
        notificationCount = 0
    }
    
    // Async image loader from url
    func imageForUrl(url: String, complete: (image: NSImage?, err: NSError?) -> Void){
        guard let imageUrl = NSURL(string: url) else {
            complete(image: nil, err: NSError(domain: NSBundle.mainBundle().bundleIdentifier ?? "main", code: 500, userInfo: ["error": "illegal url"]))
            return
        }
        let imageRequest = NSURLRequest(URL: imageUrl)
        let task = NSURLSession.sharedSession()
        task.dataTaskWithRequest(imageRequest, completionHandler: {(data, response, err) -> Void in
            if let _data = data {
                let image = NSImage(data: _data)
                complete(image: image, err: nil)
            } else {
                complete(image: nil, err: NSError(domain: NSBundle.mainBundle().bundleIdentifier ?? "main", code: err!.code, userInfo: err!.userInfo))
            }
        })
    }
    
    // @wdg Add Notification Support
    // Issue: #2
    func makeNotification (title: NSString, message: NSString, iconUrl: NSString) {
        let notification:NSUserNotification = NSUserNotification() // Set up Notification

        // If has no message (title = message)
        if (message.isEqualToString("undefined")) {
            notification.title = SETTINGS["title"] as? String // Use App name!
            notification.informativeText = title as String   // Title   = string
        } else {
            notification.title = title as String             // Title   = string
            notification.informativeText = message as String // Message = string
        }

        
        notification.soundName = NSUserNotificationDefaultSoundName // Default sound
        notification.deliveryDate = NSDate(timeIntervalSinceNow: 0) // Now!
        notification.actionButtonTitle = "Close"

        // Notification has a icon, so add it!
        if (!iconUrl.isEqualToString("undefined")) {
            imageForUrl(iconUrl as String, complete: {(image, err) in
                notification.contentImage = image
            })
        }
        
        let notificationcenter: NSUserNotificationCenter? = NSUserNotificationCenter.defaultUserNotificationCenter() // Notification centre
        notificationcenter!.scheduleNotification(notification) // Pushing to notification centre
        
        notificationCount++
        
        NSApplication.sharedApplication().dockTile.badgeLabel = String(notificationCount)
    }
    
    // @wdg Add Notification Support
    // Issue: #2
    func flashScreen (data: NSString) {
        if ((Int(data as String)) != nil || data.isEqualToString("undefined")) {
            AudioServicesPlaySystemSound(kSystemSoundID_FlashScreen)
        } else {
            let time:NSArray = (data as String).componentsSeparatedByString(",")
            for(var i = 0; i < time.count; i++) {
                var timeAsInt = NSNumberFormatter().numberFromString(time[i] as! String)
                timeAsInt = Int(timeAsInt!)/100
                NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(timeAsInt!), target: self, selector: Selector("flashScreenNow"), userInfo: nil, repeats: false)
            }
        }
    }
    
    // @wdg Add Notification Support
    // Issue: #2
    func flashScreenNow() {
        AudioServicesPlaySystemSound(kSystemSoundID_FlashScreen)
    }
    
    func evaluateScript(script: String, beforeLoad: Bool = false, crossFrame: Bool = false) {
        let userScript = WKUserScript(source: script, injectionTime: beforeLoad ? .AtDocumentStart : .AtDocumentEnd, forMainFrameOnly: !crossFrame)
        mainWebview.configuration.userContentController.addUserScript(userScript)
    }
}
