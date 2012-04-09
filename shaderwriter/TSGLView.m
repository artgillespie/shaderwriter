//
//  TSGLView.m
//  shaderwriter
//
//  Created by Gillespie Art on 4/5/12.
//  Copyright (c) 2012 tapsquare, llc. All rights reserved.
//

#import "TSGLView.h"
#import <QuartzCore/QuartzCore.h>

@implementation TSGLView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

/*
 * // Only override drawRect: if you perform custom drawing.
 * // An empty implementation adversely affects performance during animation.
 * - (void)drawRect:(CGRect)rect
 * {
 *  // Drawing code
 * }
 */

@end
