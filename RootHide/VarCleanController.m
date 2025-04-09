#import "varCleanController.h"
#include "AppDelegate.h"
#import "ZFCheckbox.h"

@interface varCleanController ()
@property (nonatomic, retain) NSMutableArray* tableData;
@end

@implementation varCleanController

+ (instancetype)sharedInstance {
    static varCleanController* sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.hidden = NO;
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.clearsSelectionOnViewWillAppear = NO;
    
    [self setTitle:Localized(@"varClean")];
    
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:Localized(@"Clean") style:UIBarButtonItemStylePlain target:self action:@selector(varClean)];
    self.navigationItem.rightBarButtonItem = button;
    
    UIBarButtonItem *button2 = [[UIBarButtonItem alloc] initWithTitle:Localized(@"SelectAll") style:UIBarButtonItemStylePlain target:self action:@selector(batchSelect)];
    self.navigationItem.leftBarButtonItem = button2;
    
    self.tableData = [[NSMutableArray alloc] init];
    
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    refreshControl.tintColor = [UIColor grayColor];
    [refreshControl addTarget:self action:@selector(manualRefresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refreshControl;
    
    
    self.tableData = [self updateData:NO];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(autoRefresh)
                                          name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)batchSelect {
    int selected = 0;
    for(NSDictionary* group in self.tableData) {
        for(NSMutableDictionary* item in group[@"items"]) {
            if(![item[@"checked"] boolValue] && ![item[@"ignored"] boolValue]) {
                item[@"checked"] = @YES;
                selected++;
            }
        }
    }
    if(selected==0) for(NSDictionary* group in self.tableData) {
        for(NSMutableDictionary* item in group[@"items"]) {
            if([item[@"checked"] boolValue]) {
                item[@"checked"] = @NO;
            }
        }
    }
    [self.tableView reloadData];
}

- (void)startRefresh:(BOOL)keepState {
    [self.tableView.refreshControl beginRefreshing];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSMutableArray* newData = [self updateData:keepState];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.tableData = newData;
            [self.tableView reloadData];
            [self.tableView.refreshControl endRefreshing];
        });
    });
}

- (void)manualRefresh {
    [self startRefresh:NO];
}

- (void)autoRefresh {
    [self startRefresh:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView.refreshControl beginRefreshing];
    [self.tableView.refreshControl endRefreshing];
}

- (void)updateForRules:(NSDictionary*)rules customed:(NSMutableDictionary*)customedRules newData:(NSMutableArray*)newData keepState:(BOOL)keepState {
    for (NSString* path in rules) {
        NSMutableArray *folders = [[NSMutableArray alloc] init];
        NSMutableArray *files = [[NSMutableArray alloc] init];
        
        NSDictionary* ruleItem = [rules objectForKey:path];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:path error:nil];
        
        NSArray *whiteList = ruleItem[@"whitelist"];
        NSArray *blackList = ruleItem[@"blacklist"];
        
        NSDictionary* customedRuleItem = customedRules[path];
        NSArray* customedWhiteList = customedRuleItem[@"whitelist"];
        NSArray* customedBlackList = customedRuleItem[@"blacklist"];
        [customedRules removeObjectForKey:path];
        
        NSMutableDictionary *tableGroup = @{
            @"group": path,
            @"items": @[]
        }.mutableCopy;
        
        for (NSString *file in contents) {
            
            BOOL checked = NO;
            BOOL ignored = NO;
            
            // blacklist priority
            if([self checkFileInList:file List:blackList])
            {
                if([self checkFileInList:file List:customedWhiteList]) {
                    ignored = YES;
                    checked = NO;
                } else {
                    checked = YES;
                }
            }
            else if([self checkFileInList:file List:customedBlackList])
            {
                checked = YES;
            }
            else if([self checkFileInList:file List:whiteList])
            {
                continue;
            }
            else if([ruleItem[@"default"] isEqualToString:@"blacklist"])
            {
                if([self checkFileInList:file List:customedWhiteList] || [customedRuleItem[@"default"] isEqualToString:@"whitelist"]) {
                    ignored = YES;
                    checked = NO;
                }
                else {
                    checked = YES;
                }
            }
            else if([ruleItem[@"default"] isEqualToString:@"whitelist"])
            {
                if([customedRuleItem[@"default"] isEqualToString:@"blacklist"]) {
                    checked = YES;
                } else {
                    continue;
                }
            }
            else
            {
                if([self checkFileInList:file List:customedWhiteList] || [customedRuleItem[@"default"] isEqualToString:@"whitelist"]) {
                    ignored = YES;
                    checked = NO;
                }
                else if([customedRuleItem[@"default"] isEqualToString:@"blacklist"]) {
                    checked = YES;
                }
                else {
                    checked = NO;
                }
            }
            
            if(keepState)
            {
                for(NSDictionary* group in self.tableData)
                {
                    if([group[@"group"] isEqualToString:path])
                    {
                        for(NSDictionary* item in group[@"items"])
                        {
                            if([item[@"name"] isEqualToString:file])
                            {
                                if(!ignored) {
                                    checked = [item[@"checked"] boolValue];
                                }
                                break;
                            }
                        }
                        break;
                    }
                }
            }
            
            NSString *filePath = [path stringByAppendingPathComponent:file];
            
            BOOL isDirectory = NO;
            BOOL exists = [fileManager fileExistsAtPath:filePath isDirectory:&isDirectory];
            BOOL isFolder = exists && isDirectory;
            
            NSMutableDictionary *tableItem = @{
                @"name": file,
                @"path": filePath,
                @"isFolder": @(isFolder),
                @"checked": @(checked),
                @"ignored": @(ignored),
            }.mutableCopy;
            
            if(isFolder) {
                [folders addObject:tableItem];
            } else {
                [files addObject:tableItem];
            }
        }
        
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        NSArray *sortedFolders = [folders sortedArrayUsingDescriptors:@[sortDescriptor]];
        NSArray *sortedFiles = [files sortedArrayUsingDescriptors:@[sortDescriptor]];
        
        tableGroup[@"items"] = [[sortedFolders arrayByAddingObjectsFromArray:sortedFiles] mutableCopy];
        [newData addObject:tableGroup];
    }
}

- (NSMutableArray*)updateData:(BOOL)keepState {
    NSLog(@"updateData...");
    NSMutableArray* newData = [[NSMutableArray alloc] init];
    
    NSString *rulesFilePath = jbroot(@"/var/mobile/Library/RootHide/varCleanRules.plist");
    NSDictionary *rules = [NSDictionary dictionaryWithContentsOfFile:rulesFilePath];
    
    NSString *customedRulesFilePath = jbroot(@"/var/mobile/Library/RootHide/varCleanRules-custom.plist");
    NSMutableDictionary *customedRules = [NSMutableDictionary dictionaryWithContentsOfFile:customedRulesFilePath];
    
    [self updateForRules:rules customed:customedRules newData:newData keepState:keepState];
    //continue processing the remaining paths that are not in the built-in list
    [self updateForRules:customedRules customed:nil newData:newData keepState:keepState];

    NSComparator sorter = ^NSComparisonResult(NSDictionary* a, NSDictionary* b)
    {
        if([a[@"items"] count]!=0 && [b[@"items"] count]==0) return NSOrderedAscending;
        if([a[@"items"] count]==0 && [b[@"items"] count]!=0) return NSOrderedDescending;
        
        return [a[@"group"] compare:b[@"group"]];
    };
    [newData sortUsingComparator:sorter];
    
    return newData;
}

- (BOOL)checkFileInList:(NSString *)fileName List:(NSArray*)list {
    for (NSObject* item in list) {
        if([item isKindOfClass:NSString.class]) {
            if ([fileName isEqualToString:(NSString*)item]) {
                return YES;
            }
        } else if([item isKindOfClass:NSDictionary.class]) {
            NSDictionary* condition = (NSDictionary*)item;
            NSString *name = condition[@"name"];
            NSString *match = condition[@"match"];
            
            if ([match isEqualToString:@"include"]) {
                if ([fileName rangeOfString:name].location != NSNotFound) {
                    return YES;
                }
            } else if ([match isEqualToString:@"regexp"]) {
                NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:name options:0 error:nil];
                NSUInteger result = [regex numberOfMatchesInString:fileName options:0 range:NSMakeRange(0, fileName.length)];
                if(result != 0) return YES;
            }
        }
    }
    return NO;
}

- (void)varClean {
    NSLog(@"self.tableData=%@", self.tableData);
    
    [self.tableView.refreshControl beginRefreshing];
    
    for(NSDictionary* group in [self.tableData copy]) {
        for(NSDictionary* item in [group[@"items"] copy])
        {
            if(![item[@"checked"] boolValue]) continue;
            
            NSLog(@"clean=%@", item);
            
            /*
            NSString* backup = jbroot(@"/var/mobile/Library/RootHide/backup");
            NSString* newpath = [backup stringByAppendingPathComponent:item[@"path"]];
            NSString* dirpath = [newpath stringByDeletingLastPathComponent];
            NSLog(@"newpath=%@, dirpath=%@", newpath, dirpath);
            if(![NSFileManager.defaultManager fileExistsAtPath:dirpath])
                [NSFileManager.defaultManager createDirectoryAtPath:dirpath
                                        withIntermediateDirectories:YES attributes:nil error:nil];
            [NSFileManager.defaultManager copyItemAtPath:item[@"path"] toPath:newpath error:nil];
            //*/
            
//            NSDirectoryEnumerator<NSString*>* enumerator = [NSFileManager.defaultManager enumeratorAtPath:item[@"path"]];
//            if(enumerator) for(NSString* subpath in enumerator)
//            {
//                NSError* err;
//                if(![NSFileManager.defaultManager removeItemAtPath:[item[@"path"] stringByAppendingPathComponent:subpath] error:&err]) {
//                    NSLog(@"clean failed=%@", err);
//                }
//            }
            
            NSError* err;
            if(![NSFileManager.defaultManager removeItemAtPath:item[@"path"] error:&err]) {
                NSLog(@"clean failed: %@", err);
                
                if(geteuid()!=0 || getegid()!=0) {
                    NSLog(@"try RootUserRemoveItemAtPath: %@", item[@"path"]);
                    BOOL RootUserRemoveItemAtPath(NSString* path);
                    BOOL __ret = RootUserRemoveItemAtPath(item[@"path"]);
                }
                
                continue;
            }
            
            NSIndexPath* indexPath = [NSIndexPath indexPathForRow:[group[@"items"] indexOfObject:item]
                                                        inSection:[self.tableData indexOfObject:group] ];
            
            [group[@"items"] removeObject:item]; //delete source data first
            
            NSLog(@"indexPath=%@", indexPath);
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationLeft];
        }
    }
    
    [self.tableView.refreshControl endRefreshing];
    
    self.tableData = [self updateData:NO];
    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSLog(@"numberOfRowsInSection=%ld", self.tableData.count);
    return self.tableData.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSDictionary *groupData = self.tableData[section];
    NSArray *items = groupData[@"items"];
    NSLog(@"numberOfRowsInSection=%ld %ld", (long)section, items.count);
    return items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSDictionary *groupData = self.tableData[section];
    return groupData[@"group"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"cellForRowAtIndexPath=%@", indexPath);
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    
    NSDictionary *groupData = self.tableData[indexPath.section];
    NSArray *items = groupData[@"items"];
    
    NSDictionary *item = items[indexPath.row];
    cell.textLabel.text =  [NSString stringWithFormat:@"%@ %@",[item[@"isFolder"] boolValue] ? @"🗂️" : @"📄", item[@"name"]];
    if([item[@"ignored"] boolValue]) {
        cell.textLabel.textColor = UIColor.grayColor;
    }
    ZFCheckbox *checkbox = [[ZFCheckbox alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    checkbox.userInteractionEnabled = FALSE; //passthrough to didSelectRowAtIndexPath
    [checkbox setSelected:[item[@"checked"] boolValue]];
    cell.accessoryView = checkbox;
    
    UILongPressGestureRecognizer *gest = [[UILongPressGestureRecognizer alloc]
                                          initWithTarget:self action:@selector(cellLongPress:)];
    [cell.contentView addGestureRecognizer:gest];
    gest.view.tag = indexPath.row | indexPath.section<<32;
    gest.minimumPressDuration = 1;
    
    return cell;
}

- (void)cellLongPress:(UIGestureRecognizer *)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateBegan)
    {
        long tag = recognizer.view.tag;
        NSIndexPath* indexPath = [NSIndexPath indexPathForRow:tag&0xFFFFFFFF inSection:tag>>32];
        
        NSDictionary *groupData = self.tableData[indexPath.section];
        NSArray *items = groupData[@"items"];
        NSMutableDictionary *item = items[indexPath.row];
        NSLog(@"open item %@", item);
        NSURL* url = [NSURL URLWithString:[@"filza://view" stringByAppendingString:
                                           [item[@"path"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] ];
        
        NSLog(@"open url %@", url);
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        UIPasteboard.generalPasteboard.string = item[@"path"];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];//
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    ZFCheckbox *checkbox = (ZFCheckbox*)cell.accessoryView;
    
    BOOL newstate = !checkbox.selected;
    
    [checkbox setSelected:newstate animated:YES];
    
    NSDictionary *groupData = self.tableData[indexPath.section];
    NSArray *items = groupData[@"items"];
    NSMutableDictionary *item = items[indexPath.row];
    item[@"checked"] = @(newstate);
    NSLog(@"select=%@", item);
}
@end
