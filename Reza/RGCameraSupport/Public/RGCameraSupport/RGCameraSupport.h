#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns NO if the output is detached, the size is unsupported, or AVFoundation rejects it.
bool RGSetCameraPhotoDimensions(AVCapturePhotoOutput *output, CMVideoDimensions dimensions) API_AVAILABLE(ios(16.0));

NS_ASSUME_NONNULL_END
