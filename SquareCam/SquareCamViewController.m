#import "SquareCamViewController.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <AssertMacros.h>

#pragma mark-

@interface SquareCamViewController (InternalMethods)
- (void)setupAVCapture;
@end

@implementation SquareCamViewController

- (void)setupAVCapture
{
	[super viewDidLoad];
    
    OCRFocusView.layer.borderColor = [UIColor redColor].CGColor;
    OCRFocusView.layer.borderWidth = 3.0f;
    
    videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionBack];
    //    videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionFront];
    //    videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset1280x720 cameraPosition:AVCaptureDevicePositionBack];
    //    videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset1920x1080 cameraPosition:AVCaptureDevicePositionBack];
    
    videoCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
    videoCamera.horizontallyMirrorFrontFacingCamera = NO;
    videoCamera.horizontallyMirrorRearFacingCamera = NO;
    
//    [videoCamera addTarget:previewImageView];
    
    
    
    CGFloat owidth = 480;
    CGFloat oheight = 640;
    CGFloat scale = owidth/self.view.frame.size.width;
    CGFloat x = OCRFocusView.frame.origin.x*scale/owidth;
    CGFloat y = OCRFocusView.frame.origin.y*scale/oheight;
    CGFloat width = OCRFocusView.frame.size.width*scale/owidth;
    CGFloat height = OCRFocusView.frame.size.height*scale/oheight;
    cropFilter = [[GPUImageCropFilter alloc] initWithCropRegion:CGRectMake(x, y, width, height)];
    previewFilter = [[GPUImageCropFilter alloc] initWithCropRegion:CGRectMake(0, 0, 1, 1)];
    adaptiveThresholdFilter = [[GPUImageAdaptiveThresholdFilter alloc] init];
    medianFilter = [[GPUImageMedianFilter alloc] init];
    
    [previewFilter addTarget:cropFilter];
    [cropFilter addTarget:adaptiveThresholdFilter];
    [adaptiveThresholdFilter addTarget:medianFilter];
    filter = medianFilter;
    
    [adaptiveThresholdFilter addTarget:OCRImageView];
    [previewFilter addTarget:previewImageView];
    [videoCamera addTarget:previewFilter];
    [videoCamera startCameraCapture];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    // Map UIDeviceOrientation to UIInterfaceOrientation.
    UIInterfaceOrientation orient = UIInterfaceOrientationPortrait;
    switch ([[UIDevice currentDevice] orientation])
    {
        case UIDeviceOrientationLandscapeLeft:
            orient = UIInterfaceOrientationLandscapeLeft;
            break;
            
        case UIDeviceOrientationLandscapeRight:
            orient = UIInterfaceOrientationLandscapeRight;
            break;
            
        case UIDeviceOrientationPortrait:
            orient = UIInterfaceOrientationPortrait;
            break;
            
        case UIDeviceOrientationPortraitUpsideDown:
            orient = UIInterfaceOrientationPortraitUpsideDown;
            break;
            
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationFaceDown:
        case UIDeviceOrientationUnknown:
            // When in doubt, stay the same.
            orient = fromInterfaceOrientation;
            break;
    }
    videoCamera.outputImageOrientation = orient;
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (interfaceOrientation == UIDeviceOrientationPortrait) {
        return YES;
    }
    return NO; // Support all orientations.
}

- (IBAction)updateSliderValue:(id)sender
{
    [adaptiveThresholdFilter setBlurRadiusInPixels:[(UISlider *)sender value]];
}

- (IBAction)toggleSwitchChange:(id)sender {
    OCRImageView.hidden = ![(UISwitch*)sender isOn];
}

- (void)dealloc
{
    [tesseract clear];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	[self setupAVCapture];
    
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    serverAddress = [ud objectForKey:@"ServerAddress"];
    if (serverAddress == nil) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Empty Server Address" message:@"please set server address in settings." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
    }
    
    isSendingResult = NO;
    isOCRing = NO;
    lock = [[NSLock alloc] init];
    
    //    [tesseract setVariableValue:@" -_!@#$%^&*()~`" forKey:@"tessedit_char_blacklist"]; //limit search
    tesseract = [[Tesseract alloc] initWithDataPath:@"tessdata" language:@"eng"];
    [tesseract setVariableValue:@"0123456789.," forKey:@"tessedit_char_whitelist"]; //limit search
    queue = [[NSOperationQueue alloc] init];
    [queue setMaxConcurrentOperationCount:1];
    sleep(2);
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(scheduleOCRTask) userInfo:nil repeats:YES];
//    [self performSelectorInBackground:@selector(scheduleOCRTask) withObject:nil];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

#pragma mark - OCR

- (void) scheduleOCRTask {
    if (!isOCRing) {
        [queue addOperationWithBlock:^{
            if (isOCRing) {
                return;
            }
            [filter useNextFrameForImageCapture];
            UIImage* curImage = [filter imageFromCurrentFramebuffer];
            if (curImage != nil) {
//                [self ocrImage:curImage];
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self ocrImage:curImage];
                });
//                [self performSelectorInBackground:@selector(ocrImage:) withObject:curImage];
            } else {
                NSLog(@"curImage is nil");
                sleep(1.0);
            }
        }];
    }
}

//- (BOOL)shouldCancelImageRecognitionForTesseract:(Tesseract*)aTesseract {
////    NSLog(@"progress:%d/100", aTesseract.progress);
//    return isSendingResult;
//}

- (void) ocrImage: (UIImage *) uiImage
{
    isOCRing = YES;
    NSLog(@"ocring...");
    [tesseract setImage:uiImage]; //image to check
    [tesseract recognize];
    currentOCRResult = [tesseract recognizedText];
    
    NSArray* words = [currentOCRResult componentsSeparatedByCharactersInSet :[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    currentOCRResult = [words componentsJoinedByString:@""];
    [self updateLabelText:currentOCRResult];
    NSLog(@"result : %@", currentOCRResult);
    isOCRing = NO;
    
//    [lock performSelectorOnMainThread:@selector(unlock) withObject:nil waitUntilDone:YES];
}

- (void)updateLabelText:(NSString *)newText {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isSendingResult) {
            return;
        }
        [OCRResultLabel setText:newText];
    });
}

# pragma mark - Server

- (void) setupServer {
//   set server address
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"settings" message:@"set server address and port" delegate:self cancelButtonTitle:@"cancel" otherButtonTitles:@"confirm", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    if (serverAddress == nil) {
        [alert textFieldAtIndex:0].placeholder = @"192.168.1.100:8000";
    } else {
        [alert textFieldAtIndex:0].placeholder = serverAddress;
    }
    [alert show];
}

- (void) sendResult:(NSString*) res {
    if (serverAddress == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:@"server address is empty."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
             [alert show];
            
        });
        return;
    }
    if (res == nil) {
        NSLog(@"nil result");
        return;
    }
    
    isSendingResult = YES;
    [self updateLabelText:@"sending..."];
    
    isSendingResult = YES;
    
    NSString* urlString = [NSString stringWithFormat:@"http://%@?res=%@", serverAddress, [res stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [[NSURLRequest alloc]initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:5];
    NSData *received = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    NSString *str = [[NSString alloc]initWithData:received encoding:NSUTF8StringEncoding];
    NSLog(@"send to server: %@",str);
    
    currentOCRResult = nil;
    isSendingResult = NO;

    [self updateLabelText:@"finish!"];
}

#pragma mark - UIAlertViewDelegate

-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
    if (buttonIndex == 1) {
        serverAddress =[alertView textFieldAtIndex:0].text;
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:serverAddress forKey:@"ServerAddress"];
        [ud synchronize];
        NSLog(@"set server address:%@", serverAddress);
    }
}

#pragma mark - OCR Outlet Actions

- (IBAction)showSettings:(id)sender {
    [self setupServer];
}

- (IBAction)sendResultToServer:(id)sender {
    if (isSendingResult) {
        return;
    }
    [self performSelectorInBackground:@selector(sendResult:) withObject:currentOCRResult];
}


@end
