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
    
    // make sure our image isn't larger in any dimension than the max texture size
    GLint maxTexture;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTexture);
    if (maxTexture < w || maxTexture < h) {
        // here we'd probably scale the image so its longest edge was == maxTexture
        NSCAssert(NO, @"Image dimensions > maxTextureSize");
    }
    
    // Draw the image into a buffer that we can hand off to OpenGL
    unsigned char *textureData = (unsigned char *)malloc(w * h * 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef textureContext = CGBitmapContextCreate(textureData, w, h, 8, w * 4,
                                                        colorSpace, kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(textureContext, 0., h);
    CGContextScaleCTM(textureContext, 1.0f, -1.f);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(textureContext, CGRectMake(0.f, 0.f, w, h), img.CGImage);

    // Generate the OpenGL texture with the image data. Note this assumes that
    // the OpenGL context we're interested in is current
    GLuint tex;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    // Enable support for Non-power-of-two textures
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, textureData);

    CGContextRelease(textureContext);
    free(textureData);
    // return the texture handle
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
@synthesize frameRateLabel = _frameRateLabel;

- (void)viewDidLoad {
    [super viewDidLoad];
    
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

    // load the default fragment shader from the bundle
    NSError *error = nil;
    NSString *shaderPath = [[NSBundle mainBundle] pathForResource:@"base" ofType:@"fsh"];
    NSAssert(nil != shaderPath, @"Couldn't find base.fsh");
    NSString *fragmentShaderSource = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&error];
    NSAssert(nil == error, @"Couldn't load fragment shader: %@", error);
        
    // compile our shaders
    _vertexShader = compileShader(kGPUImageVertexShaderString, GL_VERTEX_SHADER, &error);
    NSAssert1(nil == error, @"Vertex shader compilation failed: %@", error);
    _fragmentShader = compileShader(fragmentShaderSource, GL_FRAGMENT_SHADER, &error);
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
    _texture = textureForImage([UIImage imageNamed:@"Filters.jpg"], &error);
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

    // clear the gl buffer to gray (strictly speaking, unnecessary, but, you know...)
    glClearColor(0.1f, 0.1f, 0.1f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);

    // bind the texture containing the image we want to process to TEXTURE0 unit
    // in 3GS/iPad 1 hardware and up, you can address up to 8 texture 
    // units in the fragment shader. (i.e., TEXTURE7)
    // (source: http://developer.apple.com/library/ios/#documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/OpenGLESPlatforms/OpenGLESPlatforms.html
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _texture);

    // send the bound texture to the fragment shader's input texture uniform
    glUniform1i(_filterInputTextureUniform, 0);

    // the geometry (essentially a plane) we're going to render our texture onto
    // for image processing this will almost always be the full size of the viewport,
    // so these coordinates won't change.
    static const GLfloat vertices[] = {
        -1., -1.f,
        1.,  -1.f,
        -1., 1.f,
        1.,  1.f,
    };

    // the "coordinates" of the image to render. This maps a point on the image
    // to the geometry. So here we're basically mapping (0.0, 0.0) on the image
    // to (-1, -1) on the geometry. I think of it as pinning a decal.
    static const GLfloat textureCoordinates[] = {
        0.0f, 0.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 1.0f,
    };

    // bind and enable the position vertices to the vertex shader's position attribute
    glVertexAttribPointer(_filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices);
    glEnableVertexAttribArray(_filterPositionAttribute);
    // bind and enable the texture coordinates to the vertex shader's texture coordinate attribute
    glVertexAttribPointer(_filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates);
    glEnableVertexAttribArray(_filterTextureCoordinateAttribute);

    // draw it
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    // at this point, the processed image is in the render buffer. We could use
    // `glGetPixels()` to get the data out into a CGImage, but here we're just
    // presenting it to the screen.
    [_glContext presentRenderbuffer:_colorRenderBuffer];
}

- (void)compileFragmentShader:(id)sender {
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://10.0.1.12/~artgillespie/base.fsh"] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:5.];
    NSURLResponse *response;
    NSError *error;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    if (!data) {
        NSAssert(NO, @"Couldn't get shader from server.");
    }
    if (200 != ((NSHTTPURLResponse *)response).statusCode) {
        NSAssert(NO, @"Didn't get 200 OK status from server.");
    }
    NSString *shaderSource = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
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
}

@end
