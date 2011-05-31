/* === This file is part of Tomahawk Player - <http://tomahawk-player.org> ===
 *
 *   Copyright 2010-2011, Christian Muehlhaeuser <muesli@tomahawk-player.org>
 *
 *   Tomahawk is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   Tomahawk is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with Tomahawk. If not, see <http://www.gnu.org/licenses/>.
 */

#include "tomahawkapp_mac.h"
#include "macdelegate.h"
#include "macshortcuthandler.h"
#include <QDebug>

#import <AppKit/NSApplication.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSError.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSAppleEventManager.h>
#import <Foundation/NSURL.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSNibDeclarations.h>

#ifdef HAVE_SPARKLE
#import <Sparkle/SUUpdater.h>
#endif

// Capture global media keys on Mac (Cocoa only!)
// See: http://www.rogueamoeba.com/utm/2007/09/29/apple-keyboard-media-key-event-handling/

@interface MacApplication :NSApplication {
    AppDelegate* delegate_;
    Tomahawk::MacShortcutHandler* shortcut_handler_;
    Tomahawk::PlatformInterface* application_handler_;
}

- (Tomahawk::MacShortcutHandler*) shortcutHandler;
- (void) setShortcutHandler: (Tomahawk::MacShortcutHandler*)handler;

- (Tomahawk::PlatformInterface*) application_handler;
- (void) setApplicationHandler: (Tomahawk::PlatformInterface*)handler;
@end


@implementation AppDelegate

- (id) init {
  if ((self = [super init])) {
      application_handler_ = nil;
      shortcut_handler_ = nil;
      //dock_menu_ = nil;
  }
  return self;
}

- (id) initWithHandler: (Tomahawk::PlatformInterface*)handler {
  application_handler_ = handler;

  // Register defaults for the whitelist of apps that want to use media keys
  [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
     [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers], @"SPApplicationsNeedingMediaKeys",
      nil]];


  return self;
}

- (BOOL) applicationShouldHandleReopen: (NSApplication*)app hasVisibleWindows:(BOOL)flag {
  if (application_handler_) {
    application_handler_->activate();
  }
  return YES;
}

- (void) setDockMenu: (NSMenu*)menu {
  dock_menu_ = menu;
}

- (NSMenu*) applicationDockMenu: (NSApplication*)sender {
  return dock_menu_;
}


- (Tomahawk::MacShortcutHandler*) shortcutHandler {
    return shortcut_handler_;
}

- (void) setShortcutHandler: (Tomahawk::MacShortcutHandler*)handler {
    qDebug() << "Setting shortcut handler of MacApp";
    // should be the same as MacApplication's
  shortcut_handler_ = handler;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  key_tap_ = [[SPMediaKeyTap alloc] initWithDelegate:self];
  if([SPMediaKeyTap usesGlobalMediaKeyTap])
    [key_tap_ startWatchingMediaKeys];
  else
    qWarning()<<"Media key monitoring disabled";

}

- (void) mediaKeyTap: (SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event {
  NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");

  int key_code = (([event data1] & 0xFFFF0000) >> 16);
  int key_flags = ([event data1] & 0x0000FFFF);
  BOOL key_is_pressed = (((key_flags & 0xFF00) >> 8)) == 0xA;
  // not used. keep just in case
  //  int key_repeat = (key_flags & 0x1);

  if (!shortcut_handler_) {
    qWarning() << "No shortcut handler when we get a media key event...";
    return;
  }
  if (key_is_pressed) {
    shortcut_handler_->macMediaKeyPressed(key_code);
  }
}

- (BOOL) application: (NSApplication*)app openFile:(NSString*)filename {
  qDebug() << "Wants to open:" << [filename UTF8String];

  if (application_handler_->loadUrl(QString::fromUtf8([filename UTF8String]))) {
    return YES;
  }

  return NO;
}

- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication*) sender {
  return NSTerminateNow;
}

@end

@implementation MacApplication

- (id) init {
  if ((self = [super init])) {
      [self setShortcutHandler:nil];
      [self setApplicationHandler:nil];

      NSAppleEventManager *em = [NSAppleEventManager sharedAppleEventManager];
      [em
        setEventHandler:self
        andSelector:@selector(getUrl:withReplyEvent:)
        forEventClass:kInternetEventClass
        andEventID:kAEGetURL];
      [em
        setEventHandler:self
        andSelector:@selector(getUrl:withReplyEvent:)
        forEventClass:'WWW!'
        andEventID:'OURL'];
      NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
      OSStatus httpResult = LSSetDefaultHandlerForURLScheme((CFStringRef)@"tomahawk", (CFStringRef)bundleID);

      //TODO: Check httpResult and httpsResult for errors
  }
  return self;
}

- (Tomahawk::MacShortcutHandler*) shortcutHandler {
    return shortcut_handler_;
}

- (void) setShortcutHandler: (Tomahawk::MacShortcutHandler*)handler {
    // should be the same as AppDelegate's
  shortcut_handler_ = handler;
}

- (Tomahawk::PlatformInterface*) application_handler {
  return application_handler_;
}

- (void) setApplicationHandler: (Tomahawk::PlatformInterface*)handler {
  delegate_ = [[AppDelegate alloc] initWithHandler:handler];
  // App-shortcut-handler set before delegate is set.
  // this makes sure the delegate's shortcut_handler is set
  [delegate_ setShortcutHandler:shortcut_handler_];
  [self setDelegate:delegate_];
}

-(void) sendEvent: (NSEvent*)event {
    // If event tap is not installed, handle events that reach the app instead
    BOOL shouldHandleMediaKeyEventLocally = ![SPMediaKeyTap usesGlobalMediaKeyTap];

    if(shouldHandleMediaKeyEventLocally && [event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys) {
      [(id)[self delegate] mediaKeyTap: nil receivedMediaKeyEvent: event];
    }

    [super sendEvent: event];
}

@end

void Tomahawk::macMain() {
  [[NSAutoreleasePool alloc] init];
  // Creates and sets the magic global variable so QApplication will find it.
  [MacApplication sharedApplication];
#ifdef HAVE_SPARKLE
    // Creates and sets the magic global variable for Sparkle.
    [[SUUpdater sharedUpdater] setDelegate: NSApp];
#endif
}


void Tomahawk::setShortcutHandler(Tomahawk::MacShortcutHandler* handler) {
  [NSApp setShortcutHandler: handler];
}

void Tomahawk::setApplicationHandler(Tomahawk::PlatformInterface* handler) {
  [NSApp setApplicationHandler: handler];
}

void Tomahawk::checkForUpdates() {
#ifdef HAVE_SPARKLE
  [[SUUpdater sharedUpdater] checkForUpdates: NSApp];
#endif
}
