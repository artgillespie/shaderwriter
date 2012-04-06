//
//  TSViewController.h
//  shaderwriter
//
//  Created by Gillespie Art on 4/5/12.
//  Copyright (c) 2012 tapsquare, llc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TSGLView.h"

@interface TSViewController : UIViewController

- (IBAction)compileFragmentShader:(id)sender;
- (IBAction)saveShader:(id)sender;

@property (nonatomic, strong) IBOutlet TSGLView *glView;
@property (nonatomic, strong) IBOutlet UITextView *shaderEditor;
@property (nonatomic, strong) IBOutlet UILabel *frameRateLabel;

@end
