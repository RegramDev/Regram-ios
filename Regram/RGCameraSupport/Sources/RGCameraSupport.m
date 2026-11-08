#import <RGCameraSupport/RGCameraSupport.h>

bool RGSetCameraPhotoDimensions(AVCapturePhotoOutput *output, CMVideoDimensions dimensions) {
    if (dimensions.width <= 0 || dimensions.height <= 0) {
        return false;
    }
    AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
    for (AVCaptureInputPort *port in connection.inputPorts) {
        if (![port.mediaType isEqualToString:AVMediaTypeVideo] || ![port.input isKindOfClass:AVCaptureDeviceInput.class]) {
            continue;
        }
        AVCaptureDevice *device = ((AVCaptureDeviceInput *)port.input).device;
        for (NSValue *value in device.activeFormat.supportedMaxPhotoDimensions) {
            CMVideoDimensions supported;
            [value getValue:&supported size:sizeof(supported)];
            if (supported.width == dimensions.width && supported.height == dimensions.height) {
                // This setter raises an Objective-C exception for an unready capture graph.
                // Swift's do/catch cannot catch it, including on camera switches in a running session.
                @try {
                    if (output.maxPhotoDimensions.width != dimensions.width || output.maxPhotoDimensions.height != dimensions.height) {
                        output.maxPhotoDimensions = dimensions;
                    }
                    return true;
                } @catch (NSException *exception) {
                    return false;
                }
            }
        }
    }
    return false;
}
