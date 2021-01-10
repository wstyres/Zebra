//
//  ZBSourceTableViewCell.h
//  Zebra
//
//  Created by Andrew Abosh on 2019-05-02.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

@class ZBBaseSource;
@class ZBSourceFilter;

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface ZBSourceTableViewCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIImageView *iconImageView;
@property (weak, nonatomic) IBOutlet UILabel *sourceLabel;
@property (weak, nonatomic) IBOutlet UIView *backgroundContainerView;
@property (weak, nonatomic) IBOutlet UILabel *urlLabel;
@property (strong, nonatomic) IBOutlet UIImageView *storeBadge;
@property (weak, nonatomic) IBOutlet UILabel *installedPackagesLabel;

- (void)setSpinning:(BOOL)animated;
- (void)setDisabled:(BOOL)disabled;
- (void)setSource:(ZBBaseSource *)source withFilter:(ZBSourceFilter *)filter;
@end

NS_ASSUME_NONNULL_END
