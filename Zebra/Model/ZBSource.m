//
//  ZBSource.m
//  Zebra
//
//  Created by Wilson Styres on 11/30/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

@import UIKit;
@import SafariServices;

#import "ZBSource.h"
#import "ZBSourceManager.h"
#import "UICKeyChainStore.h"
#import <ZBAppDelegate.h>
//#import <Database/ZBDatabaseManager.h>
#import <Database/ZBColumn.h>
#import <ZBDevice.h>
#import <ZBUtils.h>
#import <JSONParsing/ZBUserInfo.h>
#import <JSONParsing/ZBSourceInfo.h>
#import <Tabs/ZBTabBarController.h>

@interface ZBSource () {
    NSURL *paymentVendorURI;
}
@end

@implementation ZBSource

@synthesize pinPriority = _pinPriority;

const char *textColumn(sqlite3_stmt *statement, int column) {
    return (const char *)sqlite3_column_text(statement, column);
}

+ (ZBSource *)localSource {
    ZBSource *local = [[ZBSource alloc] init];
    [local setOrigin:NSLocalizedString(@"Local Repository", @"")];
    [local setLabel:local.origin];
    [local setUuid:@"_var_lib_dpkg_status"];
    [local setSourceID:0];
    [local setRemote:NO];
    
    return local;
}

+ (ZBSource * _Nullable)sourceFromBaseURL:(NSString *)baseURL {
    return NULL;
//    return [[ZBDatabaseManager sharedInstance] sourceFromBaseURL:baseURL];
}

+ (ZBSource * _Nullable)sourceFromBaseFilename:(NSString *)baseFilename {
    return NULL;
//    return [[ZBDatabaseManager sharedInstance] sourceFromBaseFilename:baseFilename];
}

+ (BOOL)exists:(NSString *)urlString {
    return YES;
//    ZBDatabaseManager *databaseManager = [ZBDatabaseManager sharedInstance];
//    return [databaseManager sourceIDFromBaseURL:urlString strict:NO] > 0;
}

+ (UIImage *)imageForSection:(NSString *)section {
    NSString *imageName = [section stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    if ([imageName containsString:@"("]) {
        NSArray *components = [imageName componentsSeparatedByString:@"_("];
        if ([components count] < 2) {
            components = [imageName componentsSeparatedByString:@"("];
        }
        imageName = components[0];
    }
    
    UIImage *sectionImage = [UIImage imageNamed:imageName] ?: [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"/Applications/Zebra.app/Sections/%@.png", imageName]] ?: [UIImage imageNamed:@"Unknown"];
    return sectionImage;
}

- (id)initWithSQLiteStatement:(sqlite3_stmt *)statement {
    const char *archiveTypeChars   = textColumn(statement, ZBSourceColumnArchiveType);
    const char *repositoryURIChars = textColumn(statement, ZBSourceColumnURL);
    const char *distributionChars  = textColumn(statement, ZBSourceColumnDistribution);
    const char *componenetsChars   = textColumn(statement, ZBSourceColumnComponents);
    
    if (repositoryURIChars == 0) return NULL;
    
    NSArray *components;
    if (componenetsChars != 0 && strcmp(componenetsChars, "") != 0) {
        components = [[NSString stringWithUTF8String:componenetsChars] componentsSeparatedByString:@" "];
    }
    
    self = [super initWithArchiveType:archiveTypeChars != 0 ? [NSString stringWithUTF8String:archiveTypeChars] : @"deb" repositoryURI:[NSString stringWithUTF8String:repositoryURIChars] distribution:distributionChars != 0 ? [NSString stringWithUTF8String:distributionChars] : @"./" components:components];
    
    if (self) {
        const char *descriptionChars   = textColumn(statement, ZBSourceColumnDescription);
        const char *originChars        = textColumn(statement, ZBSourceColumnOrigin);
        const char *labelChars         = textColumn(statement, ZBSourceColumnLabel);
        const char *versionChars       = textColumn(statement, ZBSourceColumnVersion);
        const char *suiteChars         = textColumn(statement, ZBSourceColumnSuite);
        const char *codenameChars      = textColumn(statement, ZBSourceColumnCodename);
        const char *architectureChars  = textColumn(statement, ZBSourceColumnArchitectures);
//        const char *vendorChars        = textColumn(statement, ZBSourceColumnPaymentVendor);
        const char *uuidChars  = textColumn(statement, ZBSourceColumnUUID);
        
        [self setSourceDescription:descriptionChars != 0 ? [[NSString alloc] initWithUTF8String:descriptionChars] : nil];
        [self setOrigin:originChars != 0 ? [[NSString alloc] initWithUTF8String:originChars] : NSLocalizedString(@"Unknown", @"")];
        [self setLabel:[ZBUtils decodeCString:labelChars fallback:NSLocalizedString(@"Unknown", @"")]];
        [self setVersion:versionChars != 0 ? [[NSString alloc] initWithUTF8String:versionChars] : NSLocalizedString(@"Unknown", @"")];
        [self setSuite:suiteChars != 0 ? [[NSString alloc] initWithUTF8String:suiteChars] : NSLocalizedString(@"Unknown", @"")];
        [self setCodename:codenameChars != 0 ? [[NSString alloc] initWithUTF8String:codenameChars] : NSLocalizedString(@"Unknown", @"")];
        
//        if (vendorChars != 0) {
//            NSString *vendor = [[[NSString alloc] initWithUTF8String:vendorChars] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
//            self->paymentVendorURI = [[NSURL alloc] initWithString:vendor];
//        }
        
        if (architectureChars != 0) {
            NSArray *architectures = [[NSString stringWithUTF8String:architectureChars] componentsSeparatedByString:@" "];
            [self setArchitectures:architectures];
        }
        else {
            [self setArchitectures:@[@"all"]];
        }
        
        [self setUuid:uuidChars != 0 ? [[NSString alloc] initWithUTF8String:uuidChars] : nil];
//        [self setSourceID:sqlite3_column_int(statement, ZBSourceColumnSourceID)];
        [self setIconURL:[self.mainDirectoryURL URLByAppendingPathComponent:@"CydiaIcon.png"]];
        
        // prevent constant network spam
        if (!self.checkedSupportFeaturedPackages) {
            // Check for featured string
            NSURL *checkingURL = [NSURL URLWithString:@"sileo-featured.json" relativeToURL:[NSURL URLWithString:self.repositoryURI]];
            NSURLSession *session = [NSURLSession sharedSession];
            [[session dataTaskWithURL:checkingURL
                    completionHandler:^(NSData *data,
                                        NSURLResponse *response,
                                        NSError *error) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
                if (data != nil && (long)[httpResponse statusCode] != 404) {
                    [self setSupportsFeaturedPackages:YES];
                }
            }] resume];
            [self setCheckedSupportFeaturedPackages:YES];
        }
        
        _pinPriority = [[ZBSourceManager sharedInstance] pinPriorityForSource:self];
    }
    
    return self;
}

- (BOOL)canDelete {
    return ![[self uuid] isEqualToString:@"getzbra.com_repo_"];
}

- (void)authenticate:(void (^)(BOOL success, BOOL notify, NSError *_Nullable error))completion {
    if (![self suppotsPaymentAPI]) {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:412 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Source does not support Payment API", @"")}];
        completion(NO, YES, error);
        return;
    }
    
    if ([self isSignedIn]) {
        completion(YES, NO, nil);
        return;
    }
    
    NSURLComponents *components = [NSURLComponents componentsWithURL:[[self paymentVendorURL] URLByAppendingPathComponent:@"authenticate"] resolvingAgainstBaseURL:YES];
    if (![components.scheme isEqualToString:@"https"]) {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:412 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Source's payment vendor URL is not secure", @"")}];
        completion(NO, YES, error);
        return;
    }
    
    NSMutableArray *queryItems = [components queryItems] ? [[components queryItems] mutableCopy] : [NSMutableArray new];
    NSURLQueryItem *udid = [NSURLQueryItem queryItemWithName:@"udid" value:[ZBDevice UDID]];
    NSURLQueryItem *model = [NSURLQueryItem queryItemWithName:@"model" value:[ZBDevice deviceModelID]];
    [queryItems addObject:udid];
    [queryItems addObject:model];
    [components setQueryItems:queryItems];
    
    NSURL *url = [components URL];
    static SFAuthenticationSession *session;
    session = [[SFAuthenticationSession alloc] initWithURL:url callbackURLScheme:@"sileo" completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
        if (callbackURL && !error) {
            NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:callbackURL resolvingAgainstBaseURL:NO];
            NSArray *queryItems = urlComponents.queryItems;
            NSMutableDictionary *queryByKeys = [NSMutableDictionary new];
            for (NSURLQueryItem *q in queryItems) {
                [queryByKeys setValue:[q value] forKey:[q name]];
            }
            NSString *token = queryByKeys[@"token"];
            NSString *payment = queryByKeys[@"payment_secret"];
            
            UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:[ZBAppDelegate bundleID] accessGroup:nil];
            [keychain setString:token forKey:self.repositoryURI];
            
            NSString *key = [self.repositoryURI stringByAppendingString:@"payment"];
            [keychain setString:nil forKey:key];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [keychain setAccessibility:UICKeyChainStoreAccessibilityWhenPasscodeSetThisDeviceOnly
                      authenticationPolicy:UICKeyChainStoreAuthenticationPolicyUserPresence];
                
                [keychain setString:payment forKey:key];
                
                completion(YES, NO, NULL);
            });
        }
        else if (error) {
            completion(NO, !(error.domain == SFAuthenticationErrorDomain && error.code == SFAuthenticationErrorCanceledLogin), error);
            return;
        }
    }];
    
    [session start];
}

- (void)signOut API_AVAILABLE(ios(11.0)) {
    if (![self suppotsPaymentAPI]) {
//        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:412 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Source does not support Payment API", @"")}];
        return;
    }
    
    if (![self isSignedIn]) {
        return;
    }
    
    NSURL *URL = [[self paymentVendorURL] URLByAppendingPathComponent:@"sign_out"];
    if (!URL || ![URL.scheme isEqualToString:@"https"]) {
//        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:412 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Source's payment vendor URL is not secure", @"")}];
        return;
    }
    
    UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:[ZBAppDelegate bundleID] accessGroup:nil];
    NSDictionary *question = @{@"token": [keychain stringForKey:[self repositoryURI]] ?: @"none"};
    [keychain removeItemForKey:[self repositoryURI]];
    
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:question options:(NSJSONWritingOptions)0 error:nil];
    
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:URL];
    [urlRequest setHTTPMethod:@"POST"];
    [urlRequest setHTTPBody:requestData];
    
    NSURLSessionDataTask *signOutTask = [[NSURLSession sharedSession] dataTaskWithRequest:urlRequest]; // This will silently fail if there is an error
    [signOutTask resume];
}

- (BOOL)isSignedIn API_AVAILABLE(ios(11.0)) {
    UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:[ZBAppDelegate bundleID] accessGroup:nil];
    return [keychain stringForKey:self.repositoryURI] ? YES : NO;
}

- (NSString *)paymentSecret:(NSError **)error {
    __block NSString *paymentSecret = NULL;
    __block NSError *paymentError = NULL;
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSString *paymentKeychainIdentifier = [NSString stringWithFormat:@"%@payment", [self repositoryURI]];
        
        UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:[ZBAppDelegate bundleID] accessGroup:nil];
        [keychain setAccessibility:UICKeyChainStoreAccessibilityWhenPasscodeSetThisDeviceOnly
              authenticationPolicy:UICKeyChainStoreAuthenticationPolicyUserPresence];
        keychain.authenticationPrompt = NSLocalizedString(@"Authenticate to initiate purchase.", @"");
        
        paymentSecret = [keychain stringForKey:paymentKeychainIdentifier error:&paymentError];
        
        dispatch_semaphore_signal(sema);
    });
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    
    if (paymentError) {
        NSLog(@"[Zebra] Payment error: %@", paymentError);
        if (error) *error = [paymentError copy];
    }
    return paymentSecret;
}

- (NSURL *)paymentVendorURL {
    if (self->paymentVendorURI && self->paymentVendorURI.host && self->paymentVendorURI.scheme) {
        return self->paymentVendorURI;
    }
    
//    ZBDatabaseManager *databaseManager = [ZBDatabaseManager sharedInstance];
//    self->paymentVendorURI = [databaseManager paymentVendorURLForSource:self];
    return self->paymentVendorURI;
}

- (BOOL)suppotsPaymentAPI {
    NSURL *paymentVendorURL = [self paymentVendorURL];
    
    return paymentVendorURL && paymentVendorURL.host && paymentVendorURL.scheme;
}

- (void)getUserInfo:(void (^)(ZBUserInfo *info, NSError *error))completion {
    if (![self paymentVendorURL] || ![self isSignedIn]) return;
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[self paymentVendorURL] URLByAppendingPathComponent:@"user_info"]];
    
    UICKeyChainStore *keychain = [UICKeyChainStore keyChainStoreWithService:[ZBAppDelegate bundleID] accessGroup:nil];
    
    NSDictionary *requestJSON = @{@"token": [keychain stringForKey:[self repositoryURI]], @"udid": [ZBDevice UDID], @"device": [ZBDevice deviceModelID]};
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestJSON options:(NSJSONWritingOptions)0 error:nil];
    
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Zebra/%@ (%@; iOS/%@)", PACKAGE_VERSION, [ZBDevice deviceType], [[UIDevice currentDevice] systemVersion]] forHTTPHeaderField:@"User-Agent"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[requestData length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:requestData];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpReponse = (NSHTTPURLResponse *)response;
        NSInteger statusCode = [httpReponse statusCode];
        
        if (statusCode == 200 && !error) {
            NSError *parseError = NULL;
            ZBUserInfo *userInfo = [ZBUserInfo fromData:data error:&parseError];
            
            if (parseError || userInfo.error) {
                parseError ? completion(nil, parseError) : completion(nil, [NSError errorWithDomain:NSURLErrorDomain code:343 userInfo:@{NSLocalizedDescriptionKey: userInfo.error}]);
                return;
            }
            
            completion(userInfo, nil);
        }
        else if (error) {
            completion(nil, error);
        }
    }];
    
    [task resume];
}

- (void)getSourceInfo:(void (^)(ZBSourceInfo *info, NSError *error))completion {
    if (![self paymentVendorURL]) return;
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[self paymentVendorURL] URLByAppendingPathComponent:@"info"]];
    
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Zebra/%@ (%@; iOS/%@)", PACKAGE_VERSION, [ZBDevice deviceType], [[UIDevice currentDevice] systemVersion]] forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpReponse = (NSHTTPURLResponse *)response;
        NSInteger statusCode = [httpReponse statusCode];
        
        if (statusCode == 200 && !error) {
            NSError *parseError = NULL;
            ZBSourceInfo *sourceInfo = [ZBSourceInfo fromData:data error:&parseError];
            
            if (parseError) {
                completion(nil, parseError);
                return;
            }
            
            completion(sourceInfo, nil);
        }
        else if (error) {
            completion(nil, error);
        }
    }];
    
    [task resume];
}

- (NSInteger)pinPriority {
    if (self.sourceID <= 0) return 100;
    else if (_pinPriority == 0) return 500;
    else return _pinPriority;
}

@end