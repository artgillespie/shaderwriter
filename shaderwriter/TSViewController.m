//
//  TSViewController.m
//  shaderwriter
//
//  Created by Gillespie Art on 4/5/12.
//  Copyright (c) 2012 tapsquare, llc. All rights reserved.
//

#import "TSViewController.h"
#import <OpenGLES/ES2/gl.h>
#import <QuartzCore/QuartzCore.h>

#define STRINGIZE(x)        # x
#define STRINGIZE2(x)       STRINGIZE(x)
#define SHADER_STRING(text) @ STRINGIZE2(text)

NSString *const kGPUImageVertexShaderString = SHADER_STRING
    (
        attribute vec4 position;
        attribute vec4 inputTextureCoordinate;

        varying vec2 textureCoordinate;

        void main(){
            gl_Position = position;
            textureCoordinate = inputTextureCoordinate.xy;
        }
    );


NSString *const kGPUImagePassthroughFragmentShaderString = @"\
varying highp vec2 textureCoordinate;\n\
uniform sampler2D inputImageTexture;\n\
void main()\n\
{\n\
    lowp vec4 clr = texture2D(inputImageTexture, textureCoordinate);\n\
    gl_FragColor = clr;\n\
}\n";

GLuint compileShader(NSString *shaderString, GLenum type, NSError **error) {
    GLuint shader = glCreateShader(type);
    const char *source = [shaderString cStringUsingEncoding:NSASCIIStringEncoding];

    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);

    GLint compileSuccess;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compileSuccess);
    if (GL_FALSE == compileSuccess) {
        GLchar messages[256];
        glGetShaderInfoLog(shader, sizeof(messages), 0, &messages[0]);
        *error = [NSError errorWithDomain:@"OpenGLDomain" code:-255 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithCString:messages encoding:NSASCIIStringEncoding] forKey:NSLocalizedDescriptionKey]];
    }
    return shader;
}

GLuint linkProgram(GLuint vertexShader, GLuint fragmentShader, NSError **error) {
    GLuint program = glCreateProgram();

    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);

    GLint linkSuccess;
    glGetProgramiv(program, GL_LINK_STATUS, &linkSuccess);
    if (GL_FALSE == linkSuccess) {
        GLchar messages[256];
        glGetProgramInfoLog(program, sizeof(messages), 0, &messages[0]);
        *error = [NSError errorWithDomain:@"OpenGLDomain" code:-255 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithCString:messages encoding:NSASCIIStringEncoding] forKey:NSLocalizedDescriptionKey]];
    }
    return program;
}

GLuint textureForImage(UIImage *img, NSError **error) {
    GLuint w = CGImageGetWidth(img.CGImage);
    GLuint h = CGImageGetHeight(img.CGImage);
    unsigned char *textureData = (unsigned char *)malloc(w * h * 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef textureContext = CGBitmapContextCreate(textureData, w, h, 8, w * 4,
                                                        colorSpace, kCGImageAlphaPremultipliedLast);

    CGContextTranslateCTM(textureContext, 0., h);
    CGContextScaleCTM(textureContext, 1.0f, -1.f);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(textureContext, CGRectMake(0.f, 0.f, w, h), img.CGImage);

    GLuint tex;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, textureData);

    CGContextRelease(textureContext);
    free(textureData);
    return tex;
}

@interface TSViewController () {
    GLuint _fragmentShader;
    GLuint _vertexShader;
    GLuint _program;
    EAGLContext *_glContext;
    GLuint _framebuffer;
    GLuint _colorRenderBuffer;
    CADisplayLink *_displayLink;
    GLint _filterPositionAttribute;
    GLint _filterTextureCoordinateAttribute;
    GLint _filterInputTextureUniform;
    GLuint _texture;
}

- (void)update;

@end

@implementation TSViewController

@synthesize glView = _glView;
@synthesize shaderEditor = _shaderEditor;
@synthesize frameRateLabel = _frameRateLabel;

- (void)viewDidLoad {
    [super viewDidLoad];

    self.shaderEditor.text = kGPUImagePassthroughFragmentShaderString;

    // create the gl context
    _glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [EAGLContext setCurrentContext:_glContext];

    // configure the view's layer
    self.glView.layer.opaque = YES;

    // set up the FBO
    glGenFramebuffers(1, &_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glGenRenderbuffers(1, &_colorRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
    if (![_glContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.glView.layer]) {
        NSAssert(false, @"renderbufferStorage:fromDrawable failed!");
    }
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderBuffer);

    GLint w;
    GLint h;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &w);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &h);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (GL_FRAMEBUFFER_COMPLETE != status) {
        NSAssert1(false, @"failed to create complete framebuffer: %d", status);
    }

    // compile our shaders
    NSError *error = nil;
    _vertexShader = compileShader(kGPUImageVertexShaderString, GL_VERTEX_SHADER, &error);
    NSAssert1(nil == error, @"Vertex shader compilation failed: %@", error);
    _fragmentShader = compileShader(kGPUImagePassthroughFragmentShaderString, GL_FRAGMENT_SHADER, &error);
    NSAssert1(nil == error, @"Fragment shader compilation failed: %@", error);
    _program = linkProgram(_vertexShader, _fragmentShader, &error);
    NSAssert1(nil == error, @"Linking program failed: %@", error);

    _filterPositionAttribute = glGetAttribLocation(_program, "position");
    _filterTextureCoordinateAttribute = glGetAttribLocation(_program, "inputTextureCoordinate");
    _filterInputTextureUniform = glGetUniformLocation(_program, "inputImageTexture");

    glEnableVertexAttribArray(_filterPositionAttribute);
    glEnableVertexAttribArray(_filterTextureCoordinateAttribute);

    glUseProgram(_program);

    // load the image into a texture
    _texture = textureForImage([UIImage imageNamed:@"friday.jpg"], &error);
    NSAssert1(nil == error, @"Couldn't load texture: %@", error);

    glViewport(0, 0, self.glView.bounds.size.width, self.glView.bounds.size.height);

    // set up the display link
    _displayLink = [[UIScreen mainScreen] displayLinkWithTarget:self selector:@selector(update)];
    _displayLink.frameInterval = 1 / 60.f;
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)viewDidUnload {
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

- (void)update {
    static CFTimeInterval last_timestamp = 0.;

    CFTimeInterval elapsed = _displayLink.timestamp - last_timestamp;

    last_timestamp = _displayLink.timestamp;

    self.frameRateLabel.text = [NSString stringWithFormat:@"%.1f", 1. / elapsed];

    glClearColor(0.f, 0.f, 1.f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _texture);

    glUniform1i(_filterInputTextureUniform, 0);

    static const GLfloat vertices[] = {
        -.35f, -1.f,
        .35f,  -1.f,
        -.35f, 1.f,
        .35f,  1.f,
    };

    static const GLfloat textureCoordinates[] = {
        0.0f, 0.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 1.0f,
    };

    glVertexAttribPointer(_filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices);
    glEnableVertexAttribArray(_filterPositionAttribute);
    glVertexAttribPointer(_filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates);
    glEnableVertexAttribArray(_filterTextureCoordinateAttribute);

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    [_glContext presentRenderbuffer:_colorRenderBuffer];
}

- (void)compileFragmentShader:(id)sender {
    NSError *error = nil;
    NSString *shaderSource = self.shaderEditor.text;
    GLuint tmpShader = compileShader(shaderSource, GL_FRAGMENT_SHADER, &error);

    if (nil != error) {
        NSLog(@"ERROR COMPILING SHADER: %@", error.localizedDescription);
        return;
    }
    _fragmentShader = tmpShader;
    GLuint tmpProgram = linkProgram(_vertexShader, _fragmentShader, &error);
    if (nil != error) {
        NSLog(@"ERROR LINKING SHADER: %@", error.localizedDescription);
        return;
    }
    _program = tmpProgram;
    glUseProgram(_program);
    [self.shaderEditor resignFirstResponder];
}

- (void)saveShader:(id)sender {
    NSArray *docs  = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsPath = [docs objectAtIndex:0];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:docsPath]) {
        [fm createDirectoryAtPath:docsPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *shaderPath = [docsPath stringByAppendingPathComponent:@"shaderSave.fsh"];
    NSError *error = nil;
    if (![self.shaderEditor.text writeToFile:shaderPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"couldn't write shader: %@", error);
    }
}

@end
