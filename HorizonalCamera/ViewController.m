//
//  ViewController.m
//  HorizonalCamera
//
//  Created by Realank on 16/5/30.
//  Copyright © 2016年 Relaank. All rights reserved.
//


#import "ViewController.h"
#import <math.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreImage/CoreImage.h>
typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);

@interface ViewController ()

@property (strong,nonatomic) AVCaptureSession *captureSession;//负责输入和输出设备之间的数据传递
@property (strong,nonatomic) AVCaptureDeviceInput *captureDeviceInput;//负责从AVCaptureDevice获得输入数据
@property (strong,nonatomic) AVCaptureStillImageOutput *captureStillImageOutput;//照片输出流
@property (strong,nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;//相机拍摄预览图层
@property (weak, nonatomic) IBOutlet UIView *viewContainer;
@property (weak, nonatomic) IBOutlet UIButton *takeButton;//拍照按钮
@property (weak, nonatomic) IBOutlet UIButton *flashAutoButton;//自动闪光灯按钮
@property (weak, nonatomic) IBOutlet UIButton *flashOnButton;//打开闪光灯按钮
@property (weak, nonatomic) IBOutlet UIButton *flashOffButton;//关闭闪光灯按钮
@property (weak, nonatomic) IBOutlet UIImageView *focusCursor; //聚焦光标

@property (nonatomic, strong) CADisplayLink *displayLink;

@property (nonatomic, strong) CALayer *viewScopeLayer;//拍照水平线
@property (nonatomic, strong) CALayer *viewLineLayer;//拍照握持角度线

@property (nonatomic, strong) CMMotionManager * motionManager;
@property (nonatomic, assign) UIDeviceOrientation deviceOritation;
@property (nonatomic, assign) CGFloat deviceAngle;

@property (nonatomic, assign) BOOL needShowAssistantLine;
@end

@implementation ViewController

#pragma mark - 控制器视图方法
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupCamera];
    _takeButton.layer.cornerRadius = _takeButton.bounds.size.width/2;
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    
}

- (void)viewDidLayoutSubviews{
    _captureVideoPreviewLayer.frame=self.viewContainer.layer.bounds;
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self.captureSession startRunning];
    [self startMotionManager];
    [self drawHorizonalLine];
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDisplayLink)];
    self.displayLink.frameInterval = 2;
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

-(void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [self.captureSession stopRunning];
    [self stopMotionManager];
    [self dismissHorizonalLine];
    [self.displayLink invalidate];
    self.displayLink = nil;
}

-(void)dealloc{
    [self removeNotification];
}

- (void)handleDisplayLink{
    [self handleDeviceMotion:_motionManager.deviceMotion];
}

#pragma mark - setup and destruct
- (void)drawHorizonalLine{
    CALayer* containerLayer = _viewContainer.layer;
    if (!_viewScopeLayer) {
        
        _viewScopeLayer = [[CALayer alloc] init];
        _viewScopeLayer.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5].CGColor;
        CALayer* maskLayer = [[CALayer alloc]init];
        CGFloat containerWidth = containerLayer.bounds.size.width;
        CGFloat containerHeight = containerLayer.bounds.size.height;
        
        _viewScopeLayer.frame = CGRectMake(0, 0, containerWidth, containerHeight);
        maskLayer.bounds = CGRectMake(0, 0, 2*MAX(containerWidth, containerHeight), 2);
        maskLayer.position = CGPointMake(containerWidth/2, containerHeight/2);
//        _viewScopeLayer.borderColor = [[UIColor greenColor] colorWithAlphaComponent:0.6].CGColor;
//        _viewScopeLayer.borderWidth = 2;
//        [containerLayer addSublayer:_viewScopeLayer];
        containerLayer.mask = _viewScopeLayer;
        maskLayer.backgroundColor = [UIColor blackColor].CGColor;
        [_viewScopeLayer addSublayer: maskLayer];
        
        
        
    }
    CALayer* maskLayer = [[_viewScopeLayer sublayers]lastObject];
    
    maskLayer.affineTransform = CGAffineTransformMakeRotation(-_deviceAngle);
    
    CGSize size = [self sizeOfRotationAngle:_deviceAngle FromSize:containerLayer.bounds.size];
    maskLayer.bounds = CGRectMake(0, 0, size.width, size.height);
}

- (CGSize)sizeOfRotationAngle:(CGFloat)angle FromSize:(CGSize)originalSize{
    if (angle >= M_PI * 2) {
        angle = 0;
    }
    CGFloat containerWidth = originalSize.width;
    CGFloat containerHeight = originalSize.height;
    CGFloat angleB = atan(containerWidth/containerHeight);
    CGFloat margin = angle;
    if (_deviceOritation == UIDeviceOrientationPortrait) {
        if (margin > M_PI) {
            margin = 2 * M_PI - angle;
        }
        
        CGFloat width = containerWidth * sin(angleB) / sin(margin + angleB);
        CGFloat height = containerHeight / containerWidth * width;
        return CGSizeMake(width, height);
        
    }else if (_deviceOritation == UIDeviceOrientationPortraitUpsideDown){
        margin = fabs(angle - M_PI);
        
        CGFloat width = containerWidth * sin(angleB) / sin(margin + angleB);
        CGFloat height = containerHeight / containerWidth * width;
        return CGSizeMake(width, height);
    }else if (_deviceOritation == UIDeviceOrientationLandscapeLeft){
        margin = fabs(angle - 3 * M_PI_2);
        
        CGFloat height = containerWidth * sin(angleB) / sin(margin + angleB);
        CGFloat width = containerHeight / containerWidth * height;
        return CGSizeMake(width, height);
    }else{
        margin = fabs(angle - M_PI_2);
        
        CGFloat height = containerWidth * sin(angleB) / sin(margin + angleB);
        CGFloat width = containerHeight / containerWidth * height;
        return CGSizeMake(width, height);
    }
    
}

- (void)dismissHorizonalLine{
    [_viewScopeLayer removeFromSuperlayer];
    _viewScopeLayer = nil;
}

- (void)drawCameraLineForHorizonal:(BOOL)isHorizonal{
    CALayer* containerLayer = _viewContainer.layer;
    static BOOL oldHorizonal = YES;
    if (!_viewLineLayer) {
        _viewLineLayer = [[CALayer alloc]init];
        CGFloat containerWidth = containerLayer.bounds.size.width;
        CGFloat containerHeight = containerLayer.bounds.size.height;
        if (isHorizonal) {
            _viewLineLayer.bounds = CGRectMake(0, 0, 2*MAX(containerWidth, containerHeight), 2);
        }else{
            _viewLineLayer.bounds = CGRectMake(0, 0, 2, 2*MAX(containerWidth, containerHeight));
        }
        _viewLineLayer.position = CGPointMake(containerWidth/2, containerHeight/2);
        _viewLineLayer.borderColor = [[UIColor redColor] colorWithAlphaComponent:0.5].CGColor;
        _viewLineLayer.borderWidth = 2;
        [containerLayer addSublayer:_viewLineLayer];
        oldHorizonal = isHorizonal;
    }else if(oldHorizonal != isHorizonal){
        CGFloat containerWidth = containerLayer.bounds.size.width;
        CGFloat containerHeight = containerLayer.bounds.size.height;
        if (isHorizonal) {
            _viewLineLayer.bounds = CGRectMake(0, 0, 2*MAX(containerWidth, containerHeight), 2);
        }else{
            _viewLineLayer.bounds = CGRectMake(0, 0, 2, 2*MAX(containerWidth, containerHeight));
        }
        _viewLineLayer.position = CGPointMake(containerWidth/2, containerHeight/2);
        oldHorizonal = isHorizonal;
    }
    
}

- (void)dismissCameraLine{
    [_viewLineLayer removeFromSuperlayer];
    _viewLineLayer = nil;
}

- (void)startMotionManager{
    _deviceOritation = UIDeviceOrientationPortrait;
    _deviceAngle = 0;
    if (_motionManager == nil) {
        _motionManager = [[CMMotionManager alloc] init];
    }
    _motionManager.deviceMotionUpdateInterval = 1/20;
    if (_motionManager.deviceMotionAvailable) {
        [_motionManager startDeviceMotionUpdates];
    } else {
        NSLog(@"No device motion on device.");
        [self setMotionManager:nil];
    }
    
}
- (void)stopMotionManager{
    [_motionManager stopDeviceMotionUpdates];
}

- (void)handleDeviceMotion:(CMDeviceMotion *)deviceMotion{
    double x = deviceMotion.gravity.x;
    double y = deviceMotion.gravity.y;
    UIDeviceOrientation orientation;
    if (fabs(y) >= fabs(x)){
        if (y >= 0){
            orientation = UIDeviceOrientationPortraitUpsideDown;
        }
        else{
            orientation = UIDeviceOrientationPortrait;
        }
    }
    else{
        if (x >= 0){
            orientation = UIDeviceOrientationLandscapeRight;
        }
        else{
            orientation = UIDeviceOrientationLandscapeLeft;
        }
    }
    if (orientation != _deviceOritation) {
        _deviceOritation = orientation;
    }
    
    double tanAngle = atan(x/y);
    if (x >= 0 && y <= 0) {
        _deviceAngle = -tanAngle;
    }else if (x > 0 && y > 0){
        _deviceAngle = M_PI - tanAngle;
    }else if (x < 0 && y > 0){
        _deviceAngle = M_PI - tanAngle;
    }else if (x < 0 && y < 0){
        _deviceAngle = 2 * M_PI - tanAngle;
    }
    [self handleViewScope];
    //    NSLog(@"%f",_deviceAngle);
    
}

- (void)handleViewScope{
    
    _needShowAssistantLine = NO;
    for (int i = 0; i <= 4; i++) {
        CGFloat gap = _deviceAngle - i * M_PI_2;
        if (fabs(gap) < 0.45 && fabs(_motionManager.deviceMotion.gravity.z) < 0.9) {
            _needShowAssistantLine = YES;
            break;
        }
    }
    if (_needShowAssistantLine) {
//        [self drawCameraLineForHorizonal:(_deviceOritation == UIDeviceOrientationPortrait || _deviceOritation == UIDeviceOrientationPortraitUpsideDown)];
        [self drawHorizonalLine];
        
        
    }else{
//        [self dismissCameraLine];
        [self dismissHorizonalLine];
        
    }
    //    _viewScopeLayer.transform = CATransform3DMakeRotation(-_deviceAngle, 0, 0, 1);
}


- (void)setupCamera{
    
    self.focusCursor.alpha=0;
    
    //初始化会话
    _captureSession=[[AVCaptureSession alloc]init];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetPhoto]) {//设置分辨率
        _captureSession.sessionPreset=AVCaptureSessionPresetPhoto;
    }
    //获得输入设备
    AVCaptureDevice *captureDevice=[self getCameraDeviceWithPosition:AVCaptureDevicePositionBack];//取得后置摄像头
    if (!captureDevice) {
        NSLog(@"取得后置摄像头时出现问题.");
        return;
    }
    
    NSError *error=nil;
    //根据输入设备初始化设备输入对象，用于获得输入数据
    _captureDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:captureDevice error:&error];
    if (error) {
        NSLog(@"取得设备输入对象时出错，错误原因：%@",error.localizedDescription);
        return;
    }
    //初始化设备输出对象，用于获得输出数据
    _captureStillImageOutput=[[AVCaptureStillImageOutput alloc]init];
    NSDictionary *outputSettings = @{AVVideoCodecKey:AVVideoCodecJPEG};
    [_captureStillImageOutput setOutputSettings:outputSettings];//输出设置
    
    //将设备输入添加到会话中
    if ([_captureSession canAddInput:_captureDeviceInput]) {
        [_captureSession addInput:_captureDeviceInput];
    }
    
    //将设备输出添加到会话中
    if ([_captureSession canAddOutput:_captureStillImageOutput]) {
        [_captureSession addOutput:_captureStillImageOutput];
    }
    
    //创建视频预览层，用于实时展示摄像头状态
    _captureVideoPreviewLayer=[[AVCaptureVideoPreviewLayer alloc]initWithSession:self.captureSession];
    
    CALayer *layer=self.viewContainer.layer;
    layer.masksToBounds=YES;
    
    _captureVideoPreviewLayer.frame=layer.bounds;
    _captureVideoPreviewLayer.videoGravity=AVLayerVideoGravityResizeAspectFill;//填充模式
    //将视频预览层添加到界面中
    //[layer addSublayer:_captureVideoPreviewLayer];
    [layer insertSublayer:_captureVideoPreviewLayer below:self.focusCursor.layer];
    
    [self addNotificationToCaptureDevice:captureDevice];
    [self addGenstureRecognizer];
    [self setFlashModeButtonStatus];
}
#pragma mark - take camera
- (IBAction)takeButtonClick:(UIButton *)sender {
    //根据设备输出获得连接
    AVCaptureConnection *captureConnection=[self.captureStillImageOutput connectionWithMediaType:AVMediaTypeVideo];
    //根据连接取得设备输出的数据
    __block CGFloat angle = _deviceAngle;
    __weak __typeof(self) weakSelf = self;
    [self.captureStillImageOutput captureStillImageAsynchronouslyFromConnection:captureConnection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        if (imageDataSampleBuffer) {
            NSData *imageData=[AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
            UIImage *image=[UIImage imageWithData:imageData];
            
            if (self.needShowAssistantLine) {
                if (weakSelf.captureDeviceInput.device.position == AVCaptureDevicePositionFront) {
                    angle = 2*M_PI - angle;
                }
                image = [weakSelf imageByStraightenImage:image andAngle:angle shouldFlipRotation:weakSelf.captureDeviceInput.device.position == AVCaptureDevicePositionFront];
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
            //            ALAssetsLibrary *assetsLibrary=[[ALAssetsLibrary alloc]init];
            //            [assetsLibrary writeImageToSavedPhotosAlbum:[image CGImage] orientation:(ALAssetOrientation)[image imageOrientation] completionBlock:nil];
        }
        
    }];
}

//旋转一定角度
- (UIImage *)imageByStraightenImage:(UIImage *)image andAngle:(CGFloat)angle shouldFlipRotation:(BOOL)isFrontCamera
{
    if (!image) return nil;
    
    CIImage* ciImage = [CIImage imageWithCGImage:image.CGImage];
    
    ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeRotation(-M_PI/2.0)];
    CGPoint origin = [ciImage extent].origin;
    ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeTranslation(-origin.x, -origin.y)];
    
    CGFloat angleToCalcSize = angle;
    if (isFrontCamera) {
        angleToCalcSize = 2*M_PI - angle;
    }
    CGSize finalSize = [self sizeOfRotationAngle:angleToCalcSize FromSize:ciImage.extent.size];
    
    ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeRotation(2*M_PI - angle)];
    origin = [ciImage extent].origin;
    ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeTranslation(-origin.x, -origin.y)];
    
    CGPoint finalOrigin = CGPointMake((ciImage.extent.size.width - finalSize.width)/2, (ciImage.extent.size.height - finalSize.height)/2);
    ciImage = [ciImage imageByCroppingToRect:CGRectMake(finalOrigin.x, finalOrigin.y, finalSize.width, finalSize.height)];
    
    CGImageRef cgImage = [[CIContext contextWithOptions:nil] createCGImage:ciImage fromRect:[ciImage extent]];
    UIImage *outputImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    
    return outputImage;
}

#pragma mark - toggle camera
- (IBAction)toggleButtonClick:(UIButton *)sender {
    AVCaptureDevice *currentDevice=[self.captureDeviceInput device];
    AVCaptureDevicePosition currentPosition=[currentDevice position];
    [self removeNotificationFromCaptureDevice:currentDevice];
    AVCaptureDevice *toChangeDevice;
    AVCaptureDevicePosition toChangePosition=AVCaptureDevicePositionFront;
    if (currentPosition==AVCaptureDevicePositionUnspecified||currentPosition==AVCaptureDevicePositionFront) {
        toChangePosition=AVCaptureDevicePositionBack;
    }
    toChangeDevice=[self getCameraDeviceWithPosition:toChangePosition];
    [self addNotificationToCaptureDevice:toChangeDevice];
    //获得要调整的设备输入对象
    AVCaptureDeviceInput *toChangeDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:toChangeDevice error:nil];
    
    //改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.captureSession beginConfiguration];
    //移除原有输入对象
    [self.captureSession removeInput:self.captureDeviceInput];
    //添加新的输入对象
    if ([self.captureSession canAddInput:toChangeDeviceInput]) {
        [self.captureSession addInput:toChangeDeviceInput];
        self.captureDeviceInput=toChangeDeviceInput;
        
    }
    //提交会话配置
    [self.captureSession commitConfiguration];
    
    [self setFlashModeButtonStatus];
}

#pragma mark auto open flash
- (IBAction)flashAutoClick:(UIButton *)sender {
    [self setFlashMode:AVCaptureFlashModeAuto];
    [self setFlashModeButtonStatus];
}
#pragma mark open flash
- (IBAction)flashOnClick:(UIButton *)sender {
    [self setFlashMode:AVCaptureFlashModeOn];
    [self setFlashModeButtonStatus];
}
#pragma mark close flash
- (IBAction)flashOffClick:(UIButton *)sender {
    [self setFlashMode:AVCaptureFlashModeOff];
    [self setFlashModeButtonStatus];
}

#pragma mark - notification
/**
 *  给输入设备添加通知
 */
-(void)addNotificationToCaptureDevice:(AVCaptureDevice *)captureDevice{
    //注意添加区域改变捕获通知必须首先设置设备允许捕获
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        captureDevice.subjectAreaChangeMonitoringEnabled=YES;
    }];
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //捕获区域发生改变
    [notificationCenter addObserver:self selector:@selector(areaChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
-(void)removeNotificationFromCaptureDevice:(AVCaptureDevice *)captureDevice{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
/**
 *  移除所有通知
 */
-(void)removeNotification{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
}

-(void)addNotificationToCaptureSession:(AVCaptureSession *)captureSession{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //会话出错
    [notificationCenter addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:captureSession];
}

/**
 *  设备连接成功
 *
 *  @param notification 通知对象
 */
-(void)deviceConnected:(NSNotification *)notification{
    NSLog(@"设备已连接...");
}
/**
 *  设备连接断开
 *
 *  @param notification 通知对象
 */
-(void)deviceDisconnected:(NSNotification *)notification{
    NSLog(@"设备已断开.");
}
/**
 *  捕获区域改变
 *
 *  @param notification 通知对象
 */
-(void)areaChange:(NSNotification *)notification{
    //    NSLog(@"捕获区域改变...");
}

/**
 *  会话出错
 *
 *  @param notification 通知对象
 */
-(void)sessionRuntimeError:(NSNotification *)notification{
    NSLog(@"会话发生错误.");
}

#pragma mark - private methods

/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
-(AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition )position{
    NSArray *cameras= [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *camera in cameras) {
        if ([camera position]==position) {
            return camera;
        }
    }
    return nil;
}

/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
-(void)changeDeviceProperty:(PropertyChangeBlock)propertyChange{
    AVCaptureDevice *captureDevice= [self.captureDeviceInput device];
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        NSLog(@"设置设备属性过程发生错误，错误信息：%@",error.localizedDescription);
    }
}

/**
 *  设置闪光灯模式
 *
 *  @param flashMode 闪光灯模式
 */
-(void)setFlashMode:(AVCaptureFlashMode )flashMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFlashModeSupported:flashMode]) {
            [captureDevice setFlashMode:flashMode];
        }
    }];
}
/**
 *  设置聚焦模式
 *
 *  @param focusMode 聚焦模式
 */
-(void)setFocusMode:(AVCaptureFocusMode )focusMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:focusMode];
        }
    }];
}
/**
 *  设置曝光模式
 *
 *  @param exposureMode 曝光模式
 */
-(void)setExposureMode:(AVCaptureExposureMode)exposureMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:exposureMode];
        }
    }];
}
/**
 *  设置聚焦点
 *
 *  @param point 聚焦点
 */
-(void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported]) {
            [captureDevice setFocusPointOfInterest:point];
        }
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        if ([captureDevice isExposurePointOfInterestSupported]) {
            [captureDevice setExposurePointOfInterest:point];
        }
    }];
}

/**
 *  添加点按手势，点按时聚焦
 */
-(void)addGenstureRecognizer{
    UITapGestureRecognizer *tapGesture=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapScreen:)];
    [self.viewContainer addGestureRecognizer:tapGesture];
}
-(void)tapScreen:(UITapGestureRecognizer *)tapGesture{
    CGPoint point= [tapGesture locationInView:self.viewContainer];
    //将UI坐标转化为摄像头坐标
    CGPoint cameraPoint= [self.captureVideoPreviewLayer captureDevicePointOfInterestForPoint:point];
    [self setFocusCursorWithPoint:point];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposureMode:AVCaptureExposureModeAutoExpose atPoint:cameraPoint];
}

/**
 *  设置闪光灯按钮状态
 */
-(void)setFlashModeButtonStatus{
    AVCaptureDevice *captureDevice=[self.captureDeviceInput device];
    AVCaptureFlashMode flashMode=captureDevice.flashMode;
    if([captureDevice isFlashAvailable]){
        self.flashAutoButton.hidden=NO;
        self.flashOnButton.hidden=NO;
        self.flashOffButton.hidden=NO;
        self.flashAutoButton.enabled=YES;
        self.flashOnButton.enabled=YES;
        self.flashOffButton.enabled=YES;
        switch (flashMode) {
            case AVCaptureFlashModeAuto:
                self.flashAutoButton.enabled=NO;
                break;
            case AVCaptureFlashModeOn:
                self.flashOnButton.enabled=NO;
                break;
            case AVCaptureFlashModeOff:
                self.flashOffButton.enabled=NO;
                break;
            default:
                break;
        }
    }else{
        self.flashAutoButton.hidden=YES;
        self.flashOnButton.hidden=YES;
        self.flashOffButton.hidden=YES;
    }
}

/**
 *  设置聚焦光标位置
 *
 *  @param point 光标位置
 */
-(void)setFocusCursorWithPoint:(CGPoint)point{
    self.focusCursor.center=point;
    self.focusCursor.transform=CGAffineTransformMakeScale(1.5, 1.5);
    self.focusCursor.alpha=1.0;
    __weak __typeof(self) weakSelf = self;
    [UIView animateWithDuration:1.0 animations:^{
        weakSelf.focusCursor.transform=CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        weakSelf.focusCursor.alpha=0;
        
    }];
}
@end