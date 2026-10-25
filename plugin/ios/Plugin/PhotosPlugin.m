#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

CAP_PLUGIN(PhotosPlugin, "Photos",
           CAP_PLUGIN_METHOD(requestPermission, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(checkPermission, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getCount, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getPhotos, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getImage, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(deletePhotos, CAPPluginReturnPromise);
)
