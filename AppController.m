//
//  AppController.m
//  Telephone
//
//  Copyright (c) 2008 Alexei Kuznetsov. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//  3. The name of the author may not be used to endorse or promote products
//     derived from this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY ALEXEI KUZNETSOV "AS IS" AND ANY EXPRESS
//  OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
//  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
//  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//  OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//  EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import <CoreAudio/CoreAudio.h>

#import "AppController.h"
#import "AKAccountController.h"
#import "AKCallController.h"
#import "AKPreferenceController.h"
#import "AKTelephone.h"
#import "AKTelephoneAccount.h"
#import "AKTelephoneCall.h"


// AudioHardware callback to track adding/removing audio devices
static OSStatus AKAudioDevicesChanged(AudioHardwarePropertyID propertyID, void *clientData);
// Get audio devices data.
static OSStatus AKGetAudioDevices(Ptr *devices, UInt16 *devicesCount);

// Audio device dictionary keys.
NSString * const AKAudioDeviceIdentifier = @"AKAudioDeviceIdentifier";
NSString * const AKAudioDeviceName = @"AKAudioDeviceName";
NSString * const AKAudioDeviceInputsCount = @"AKAudioDeviceInputsCount";
NSString * const AKAudioDeviceOutputsCount = @"AKAudioDeviceOutputsCount";

@interface AppController()

- (void)setSelectedSoundIOToTelephone;
- (void)stopTelephoneSoundTick:(NSTimer *)theTimer;

@end

@implementation AppController

@synthesize telephone;
@synthesize accountControllers;
@synthesize preferenceController;
@synthesize audioDevices;
@synthesize soundInputDeviceIndex;
@synthesize soundOutputDeviceIndex;
@synthesize incomingCallSound;
@synthesize incomingCallSoundTimer;
@dynamic hasIncomingCallControllers;

- (BOOL)hasIncomingCallControllers
{
	for (AKAccountController *anAccountController in [[[self accountControllers] copy] autorelease]) {
		for (AKCallController *aCallController in [[[anAccountController callControllers] copy] autorelease])
			if ([[aCallController call] identifier] != AKTelephoneInvalidIdentifier &&
				[[aCallController call] state] == AKTelephoneCallIncomingState)
				return YES;
	}
	
	return NO;
}

+ (void)initialize
{
	// Register defaults
	static BOOL initialized = NO;
	
	if (!initialized) {
		NSMutableDictionary *defaultsDict = [NSMutableDictionary dictionary];
		
		[defaultsDict setObject:@"" forKey:AKSTUNServerHost];
		[defaultsDict setObject:[NSNumber numberWithInteger:3478] forKey:AKSTUNServerPort];
		[defaultsDict setObject:[NSNumber numberWithBool:YES] forKey:AKVoiceActivityDetection];
		[defaultsDict setObject:@"~/Library/Logs/Telephone.log" forKey:AKLogFileName];
		[defaultsDict setObject:[NSNumber numberWithInteger:3] forKey:AKLogLevel];
		[defaultsDict setObject:[NSNumber numberWithInteger:0] forKey:AKConsoleLogLevel];
		[defaultsDict setObject:[NSNumber numberWithInteger:0] forKey:AKTransportPort];
		[defaultsDict setObject:@"Purr" forKey:AKRingingSound];
		[defaultsDict setObject:[NSNumber numberWithBool:YES] forKey:AKFormatTelephoneNumbers];
		[defaultsDict setObject:[NSNumber numberWithBool:NO] forKey:AKTelephoneNumberFormatterSplitsLastFourDigits];
		
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaultsDict];
		
		initialized = YES;
	}
}

- (id)init
{
	self = [super init];
	if (self == nil)
		return nil;
	
	telephone = [AKTelephone telephoneWithDelegate:self];
	accountControllers = [[NSMutableArray alloc] init];
	[self setPreferenceController:nil];
	audioDevices = [[NSMutableArray alloc] init];
	[self setSoundInputDeviceIndex:AKTelephoneInvalidIdentifier];
	[self setSoundOutputDeviceIndex:AKTelephoneInvalidIdentifier];
	[self setIncomingCallSoundTimer:nil];
	
	// Subscribe to Early and Confirmed call states to set sound IO to Telephone.
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	[notificationCenter addObserver:self
						   selector:@selector(telephoneCallCalling:)
							   name:AKTelephoneCallCallingNotification
							 object:nil];
	[notificationCenter addObserver:self
						   selector:@selector(telephoneCallIncoming:)
							   name:AKTelephoneCallIncomingNotification
							 object:nil];
	[notificationCenter addObserver:self
						   selector:@selector(telephoneCallDidDisconnect:)
							   name:AKTelephoneCallDidDisconnectNotification
							 object:nil];
	return self;
}

- (void)dealloc
{
	[telephone dealloc];
	[accountControllers release];
	
	if ([[[self preferenceController] delegate] isEqual:self])
		[[self preferenceController] setDelegate:nil];
	[preferenceController release];
	
	[audioDevices release];
	[incomingCallSound release];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[super dealloc];
}

// Application control starts here
- (void)awakeFromNib
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[telephone setSTUNServerHost:[defaults stringForKey:AKSTUNServerHost]];
	[telephone setSTUNServerPort:[[defaults objectForKey:AKSTUNServerPort] integerValue]];
	[telephone setUserAgentString:@"Telephone 0.8.3"];
	[telephone setLogFileName:[defaults stringForKey:AKLogFileName]];
	[telephone setLogLevel:[[defaults objectForKey:AKLogLevel] integerValue]];
	[telephone setConsoleLogLevel:[[defaults objectForKey:AKConsoleLogLevel] integerValue]];
	[telephone setDetectsVoiceActivity:[[defaults objectForKey:AKVoiceActivityDetection] boolValue]];
	[telephone setTransportPort:[[defaults objectForKey:AKTransportPort] integerValue]];
	
	[self setIncomingCallSound:[NSSound soundNamed:[defaults stringForKey:AKRingingSound]]];
	
	// Install audio devices changes callback
	AudioHardwareAddPropertyListener(kAudioHardwarePropertyDevices, AKAudioDevicesChanged, self);
	
	// Get available audio devices, select devices for sound input and output.
	[self updateAudioDevices];
	
	// Read accounts from defaults
	NSArray *savedAccounts = [defaults arrayForKey:AKAccounts];
	
	// Setup an account on first launch.
	if ([savedAccounts count] == 0) {			// There are no saved accounts, prompt user to add one.
		// Disable Preferences during the first account prompt.
		[preferencesMenuItem setAction:NULL];
		
		preferenceController = [[AKPreferenceController alloc] init];
		[[self preferenceController] setDelegate:self];
		[NSBundle loadNibNamed:@"AddAccount" owner:[self preferenceController]];
		
		// Subscribe to addAccountWindow close to terminate application.
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(windowWillClose:)
													 name:NSWindowWillCloseNotification
												   object:[[self preferenceController] addAccountWindow]];
		
		// Set different targets and actions of addAccountWindow buttons to add the first account.
		[[[self preferenceController] addAccountWindowDefaultButton] setTarget:self];
		[[[self preferenceController] addAccountWindowDefaultButton] setAction:@selector(addAccountOnFirstLaunch:)];
		[[[self preferenceController] addAccountWindowOtherButton] setTarget:[[self preferenceController] addAccountWindow]];
		[[[self preferenceController] addAccountWindowOtherButton] setAction:@selector(performClose:)];
		
		[[[self preferenceController] addAccountWindow] center];
		[[[self preferenceController] addAccountWindow] makeKeyAndOrderFront:self];
		
		return;
	}
	
	NSDictionary *accountDict;
	AKAccountController *anAccountController;
	
	// There are saved accounts, open account windows.
	for (NSUInteger i = 0; i < [savedAccounts count]; ++i) {
		accountDict = [savedAccounts objectAtIndex:i];
		
		NSString *fullName = [accountDict objectForKey:AKFullName];
		NSString *SIPAddress = [accountDict objectForKey:AKSIPAddress];
		NSString *registrar = [accountDict objectForKey:AKRegistrar];
		NSString *realm = [accountDict objectForKey:AKRealm];
		NSString *username = [accountDict objectForKey:AKUsername];
		
		anAccountController = [[AKAccountController alloc] initWithFullName:fullName
																 SIPAddress:SIPAddress
																  registrar:registrar
																	  realm:realm
																   username:username];
		
		[anAccountController setEnabled:[[accountDict objectForKey:AKAccountEnabled] boolValue]];
		[[anAccountController window] setTitle:[[anAccountController account] SIPAddress]];
		
		[[self accountControllers] addObject:anAccountController];
		
		if (![anAccountController isEnabled])
			continue;
		
		if (i == 0)
			[[anAccountController window] makeKeyAndOrderFront:self];
		else {
			NSWindow *previousAccountWindow = [[[self accountControllers] objectAtIndex:(i - 1)] window];
			[[anAccountController window] orderWindow:NSWindowBelow relativeTo:[previousAccountWindow windowNumber]];
		}
		
		[anAccountController release];
	}
	
	// Add accounts to Telephone.
	for (anAccountController in [self accountControllers]) {
		if (![anAccountController isEnabled])
			continue;

		[anAccountController setAccountRegistered:YES];
		
		// Don't add subsequent accounts if Telephone could not start.
		if (![[self telephone] started])
			break;
	}
}

- (void)updateAudioDevices
{
	OSStatus err = noErr;
    UInt32 size = 0;
	NSUInteger i = 0;
	AudioBufferList *theBufferList = NULL;
	
	// Flush current devices array.
	[[self audioDevices] removeAllObjects];
	
	// Fetch a pointer to the list of available devices.
	AudioDeviceID *devices = NULL;
	UInt16 devicesCount = 0;
	err = AKGetAudioDevices((Ptr *)&devices, &devicesCount);
	if (err != noErr)
		return;
	
	// Iterate over each device gathering information.
	for (NSUInteger loopCount = 0; loopCount < devicesCount; ++loopCount) {
		NSMutableDictionary *deviceDict = [[NSMutableDictionary alloc] init];
		
		// Get device identifier.
		NSUInteger deviceIdentifier = devices[loopCount];
		[deviceDict setObject:[NSNumber numberWithUnsignedInteger:deviceIdentifier]
					   forKey: AKAudioDeviceIdentifier];
		
		// Get device name.
		CFStringRef tempStringRef = NULL;
		size = sizeof(CFStringRef);
		err = AudioDeviceGetProperty(devices[loopCount], 0, 0, kAudioDevicePropertyDeviceNameCFString, &size, &tempStringRef);
		[deviceDict setObject:(NSString *)tempStringRef forKey:AKAudioDeviceName];
		CFRelease(tempStringRef);
		
		// Get number of input channels.
		size = 0;
		NSUInteger inputChannelsCount = 0;
		err = AudioDeviceGetPropertyInfo(devices[loopCount], 0, 1, kAudioDevicePropertyStreamConfiguration, &size, NULL);
		if ((err == noErr) && (size != 0)) {
			theBufferList = (AudioBufferList *)malloc(size);
			if (theBufferList != NULL) {
				// Get the input stream configuration.
				err = AudioDeviceGetProperty(devices[loopCount], 0, 1, kAudioDevicePropertyStreamConfiguration, &size, theBufferList);
				if (err == noErr) {
					// Count the total number of input channels in the stream.
					for(i = 0; i < theBufferList->mNumberBuffers; ++i)
						inputChannelsCount += theBufferList->mBuffers[i].mNumberChannels;
				}
				free(theBufferList);
				
				[deviceDict setObject:[NSNumber numberWithUnsignedInteger:inputChannelsCount]
							   forKey:AKAudioDeviceInputsCount];
			}
		}
		
		// Get number of output channels.
		size = 0;
		NSUInteger outputChannelsCount = 0;
		err = AudioDeviceGetPropertyInfo(devices[loopCount], 0, 0, kAudioDevicePropertyStreamConfiguration, &size, NULL);
		if((err == noErr) && (size != 0)) {
			theBufferList = (AudioBufferList *)malloc(size);
			if(theBufferList != NULL) {
				// Get the input stream configuration.
				err = AudioDeviceGetProperty(devices[loopCount], 0, 0, kAudioDevicePropertyStreamConfiguration, &size, theBufferList);
				if(err == noErr) {
					// Count the total number of output channels in the stream.
					for (i = 0; i < theBufferList->mNumberBuffers; ++i)
						outputChannelsCount += theBufferList->mBuffers[i].mNumberChannels;
				}
				free(theBufferList);
				
				[deviceDict setObject:[NSNumber numberWithUnsignedInteger:outputChannelsCount]
							   forKey:AKAudioDeviceOutputsCount];
			}
		}
		
		[[self audioDevices] addObject:deviceDict];
		[deviceDict release];
	}
	
	// Update audio devices in Telephone.
	[[self telephone] performSelectorOnMainThread:@selector(updateAudioDevices)
									   withObject:nil
									waitUntilDone:YES];
	
	// Select sound IO from the updated audio devices list.
	// This method will change sound IO in Telephone if there are active calls.
	[self selectSoundIO];
	
	// Update audio devices in preferences.
	[[self preferenceController] updateAudioDevices];
}

// Select appropriate sound IO from the list of available audio devices.
// Lookup in the defaults database for devices selected earlier. If not found, use first matched.
// Select sound IO at Telephone if there are active calls.
- (void)selectSoundIO
{
	NSArray *devices = [self audioDevices];
	NSInteger newSoundInput, newSoundOutput;
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary *deviceDict;
	NSInteger i;
	
	// Lookup devices records in the defaults.
	
	newSoundInput = newSoundOutput = NSNotFound;
	
	NSString *lastSoundInputString = [defaults objectForKey:AKSoundInput];
	if (lastSoundInputString != nil) {
		for (i = 0; i < [devices count]; ++i) {
			deviceDict = [devices objectAtIndex:i];
			if ([[deviceDict objectForKey:AKAudioDeviceName] isEqual:lastSoundInputString] &&
				[[deviceDict objectForKey:AKAudioDeviceInputsCount] integerValue] > 0)
			{
				newSoundInput = i;
				break;
			}
		}
	}
	
	NSString *lastSoundOutputString = [defaults objectForKey:AKSoundOutput];
	if (lastSoundOutputString != nil) {
		for (i = 0; i < [devices count]; ++i) {
			deviceDict = [devices objectAtIndex:i];
			if ([[deviceDict objectForKey:AKAudioDeviceName] isEqual:lastSoundOutputString] &&
				[[deviceDict objectForKey:AKAudioDeviceOutputsCount] integerValue] > 0)
			{
				newSoundOutput = i;
				break;
			}
		}
	}
	
	// If still not found, select first matched.
	
	if (newSoundInput == NSNotFound) {
		for (i = 0; i < [devices count]; ++i)
			if ([[[devices objectAtIndex:i] objectForKey:AKAudioDeviceInputsCount] integerValue] > 0) {
				newSoundInput = i;
				break;
			}
	}
	
	if (newSoundOutput == NSNotFound) {
		for (i = 0; i < [devices count]; ++i)
			if ([[[devices objectAtIndex:i] objectForKey:AKAudioDeviceOutputsCount] integerValue] > 0) {
				newSoundOutput = i;
				break;
			}
	}
	
	[self setSoundInputDeviceIndex:newSoundInput];
	[self setSoundOutputDeviceIndex:newSoundOutput];
	
	// Set selected sound IO to Telephone if there are active calls.
	if ([[self telephone] activeCallsCount] > 0)
		[self performSelectorOnMainThread:@selector(setSelectedSoundIOToTelephone)
							   withObject:nil
							waitUntilDone:NO];
}

- (void)setSelectedSoundIOToTelephone
{
	[[self telephone] setSoundInputDevice:[self soundInputDeviceIndex]
						soundOutputDevice:[self soundOutputDeviceIndex]];
}

- (void)stopTelephoneSoundTick:(NSTimer *)theTimer
{
	if ([[self telephone] activeCallsCount] == 0 && ![[self telephone] soundStopped])
		[[self telephone] stopSound];
}

- (IBAction)showPreferencePanel:(id)sender
{
	if (preferenceController == nil) {
		preferenceController = [[AKPreferenceController alloc] init];
		[[self preferenceController] setDelegate:self];
	}
	
	if (![[[self preferenceController] window] isVisible])
		[[[self preferenceController] window] center];
	
	[[self preferenceController] showWindow:nil];
}
		 
- (IBAction)addAccountOnFirstLaunch:(id)sender
{
	[[self preferenceController] addAccount:sender];
	
	// Re-enable Preferences.
	[preferencesMenuItem setAction:@selector(showPreferencePanel:)];
	
	// Change back targets and actions of addAccountWindow buttons.
	[[[self preferenceController] addAccountWindowDefaultButton] setTarget:[self preferenceController]];
	[[[self preferenceController] addAccountWindowDefaultButton] setAction:@selector(addAccount:)];
	[[[self preferenceController] addAccountWindowOtherButton] setTarget:[self preferenceController]];
	[[[self preferenceController] addAccountWindowOtherButton] setAction:@selector(closeSheet:)];
}

- (void)startIncomingCallSoundTimer
{
	if ([self incomingCallSoundTimer] != nil)
		[[self incomingCallSoundTimer] invalidate];
	
	[self setIncomingCallSoundTimer:[NSTimer scheduledTimerWithTimeInterval:4
																	 target:self
																   selector:@selector(incomingCallSoundTimerTick:)
																   userInfo:nil
																	repeats:YES]];
}

- (void)stopIncomingCallSoundTimer
{
	if (![self hasIncomingCallControllers] && [self incomingCallSoundTimer] != nil) {
		[[self incomingCallSoundTimer] invalidate];
		[self setIncomingCallSoundTimer:nil];
	}
}

- (void)incomingCallSoundTimerTick:(NSTimer *)theTimer
{
	[[self incomingCallSound] play];
}


#pragma mark -
#pragma mark AKPreferenceController delegate

- (void)preferenceControllerDidAddAccount:(NSNotification *)notification
{
	NSDictionary *accountDict = [notification userInfo];
	AKAccountController *theAccountController =	[[[AKAccountController alloc]
												  initWithFullName:[accountDict objectForKey:AKFullName]
												  SIPAddress:[accountDict objectForKey:AKSIPAddress]
												  registrar:[accountDict objectForKey:AKRegistrar]
												  realm:[accountDict objectForKey:AKRealm]
												  username:[accountDict objectForKey:AKUsername]]
												 autorelease];
	
	[[self accountControllers] addObject:theAccountController];
	
	[[theAccountController window] setTitle:[[theAccountController account] SIPAddress]];
	[[theAccountController window] orderFront:self];
	
	// Register account.
	[theAccountController setAccountRegistered:YES];
}

- (void)preferenceControllerDidRemoveAccount:(NSNotification *)notification
{
	NSInteger index = [[[notification userInfo] objectForKey:AKAccountIndex] integerValue];
	AKAccountController *anAccountController = [[self accountControllers] objectAtIndex:index];
	
	if ([anAccountController isEnabled])
		[[self telephone] removeAccount:[anAccountController account]];
	
	[[self accountControllers] removeObjectAtIndex:index];
	[[anAccountController window] orderOut:nil];
}

- (void)preferenceControllerDidChangeAccountEnabled:(NSNotification *)notification
{
	NSUInteger index = [[[notification userInfo] objectForKey:AKAccountIndex] integerValue];
	AKAccountController *theAccountController = [[self accountControllers] objectAtIndex:index];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray *savedAccounts = [defaults arrayForKey:AKAccounts];
	NSDictionary *accountDict = [savedAccounts objectAtIndex:index];
	[theAccountController setEnabled:[[accountDict objectForKey:AKAccountEnabled] boolValue]];
	
	if ([theAccountController isEnabled]) {
		[[theAccountController window] orderFront:nil];
		
		// Register account (as a result, it will be added to Telephone).
		[theAccountController setAccountRegistered:YES];
	} else {
		// Remove account from Telephone.
		[[self telephone] removeAccount:[theAccountController account]];
		
		[[theAccountController window] orderOut:nil];
	}
}

- (void)preferenceControllerDidChangeSTUNServer:(NSNotification *)notification
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if (![[self telephone] started]) {
		[[self telephone] setSTUNServerHost:[defaults stringForKey:AKSTUNServerHost]];
		[[self telephone] setSTUNServerPort:[[defaults objectForKey:AKSTUNServerPort] integerValue]];
		
		return;
	}
	
	AKAccountController *anAccountController;
	
	// Unregister accounts.
	for (anAccountController in [self accountControllers])
		if ([anAccountController isEnabled])
			[[anAccountController account] setRegistered:NO];
	
	// Wait one second to receive unregistrations confirmations.
	sleep(1);
	
	// Remove accounts from Telephone.
	for (anAccountController in [self accountControllers]) {
		[anAccountController showOfflineMode];
		[[anAccountController window] display];
		
		// Remove account from Telephone.
		[[self telephone] removeAccount:[anAccountController account]];
	}

	[[self telephone] destroyUserAgent];
	[[self telephone] setSTUNServerHost:[defaults stringForKey:AKSTUNServerHost]];
	[[self telephone] setSTUNServerPort:[[defaults objectForKey:AKSTUNServerPort] integerValue]];
	
	
	// Add accounts to Telephone.
	for (anAccountController in [self accountControllers]) {
		if (![anAccountController isEnabled])
			continue;
		
		[anAccountController setAccountRegistered:YES];
		
		// Don't add subsequent accounts if Telephone could not start.
		if (![[self telephone] started])
			break;
	}
}


#pragma mark -
#pragma mark AKTelephoneDelegate protocol

// This method decides whether Telephone should add an account.
// Telephone is started in this method if needed.
- (BOOL)telephoneShouldAddAccount:(AKTelephoneAccount *)anAccount
{
	BOOL started;
	if ([[self telephone] started])
		return YES;
	else
		started = [[self telephone] startUserAgent];
	
	if (!started) {
		NSLog(@"Could not start Telephone agent. Please check your network connection and STUN server settings.");
		
		// Display application modal alert.
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:@"OK"];
		[alert setMessageText:@"Could not start Telephone agent."];
		[alert setInformativeText:@"Please check your network connection and STUN server settings."];
		[alert runModal];
		
		return NO;
	}
	
	return YES;
}


#pragma mark -
#pragma mark NSWindow notifications

- (void)windowWillClose:(NSNotification *)notification
{
	// User closed addAccountWindow. Terminate application.
	if ([[notification object] isEqual:[[self preferenceController] addAccountWindow]]) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:NSWindowWillCloseNotification
													  object:[[self preferenceController] addAccountWindow]];
		[NSApp terminate:self];
	}
}


#pragma mark -
#pragma mark NSApplication delegate methods

// Reopen all account windows when the user clicks the dock icon.
- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
	for (AKAccountController *anAccountController in [self accountControllers]) {
		if ([anAccountController isEnabled] && ![[anAccountController window] isVisible])
			[anAccountController showWindow:nil];
	}
	
	return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	for (AKTelephoneAccount *anAccount in [[self telephone] accounts])
		if ([[anAccount calls] count] > 0) {
			NSAlert *alert = [[[NSAlert alloc] init] autorelease];
			[alert addButtonWithTitle:@"Quit"];
			[alert addButtonWithTitle:@"Cancel"];
			[alert setMessageText:@"Are you shure you want to quit Telephone?"];
			[alert setInformativeText:@"All active calls will be disconnected."];
			
			NSInteger choice = [alert runModal];
			if (choice == NSAlertFirstButtonReturn)
				return NSTerminateNow;
			else if (choice == NSAlertSecondButtonReturn)
				return NSTerminateCancel;
		}
	
	return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	// Remove all accounts.
	[[self accountControllers] removeAllObjects];
	
	BOOL destroyed = [[self telephone] destroyUserAgent];
	if (!destroyed)
		NSLog(@"Error destroying user agent");
}


#pragma mark -
#pragma mark AKTelephoneCall notifications

- (void)telephoneCallCalling:(NSNotification *)notification
{
	if ([[self telephone] activeCallsCount] > 0 && [[self telephone] soundStopped])
		[self setSelectedSoundIOToTelephone];
}

- (void)telephoneCallIncoming:(NSNotification *)notification
{
	if ([[self telephone] activeCallsCount] > 0 && [[self telephone] soundStopped])
		[self setSelectedSoundIOToTelephone];
}

- (void)telephoneCallDidDisconnect:(NSNotification *)notification
{
	[NSTimer scheduledTimerWithTimeInterval:1
									 target:self
								   selector:@selector(stopTelephoneSoundTick:)
								   userInfo:nil
									repeats:NO];
}

@end


#pragma mark -

// Send updateAudioDevices to AppController.
static OSStatus AKAudioDevicesChanged(AudioHardwarePropertyID propertyID, void *clientData)
{
	AppController *appController = (AppController *)clientData;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	if (propertyID == kAudioHardwarePropertyDevices) {
		[NSObject cancelPreviousPerformRequestsWithTarget:appController
												 selector:@selector(updateAudioDevices)
												   object:nil];
		[appController performSelector:@selector(updateAudioDevices)
							withObject:nil
							afterDelay:0.2];
	} else
		NSLog(@"Not handling this property id");
	
	[pool drain];
	
	return noErr;
}

static OSStatus AKGetAudioDevices(Ptr *devices, UInt16 *devicesCount)
{
    OSStatus err = noErr;
    UInt32 size;
    Boolean isWritable;
    
	// Get sound devices count.
    err = AudioHardwareGetPropertyInfo(kAudioHardwarePropertyDevices, &size, &isWritable);
    if (err != noErr)
		return err;
	
	*devicesCount = size / sizeof(AudioDeviceID);
    if (*devicesCount < 1)
		return err;
    
    // Allocate space for devcies.
    *devices = (Ptr)malloc(size);
    memset(*devices, 0, size);
	
	// Get the data.
    err = AudioHardwareGetProperty(kAudioHardwarePropertyDevices, &size, (void *)*devices);	
    if (err != noErr)
		return err;
	
    return err;
}
