#import <Quartz/Quartz.h>

@interface QCOpenLaseTracePlugIn : QCPlugIn
{
	bool initialized;
	
	OLTraceCtx *trace_ctx;
	OLTraceParams tparams;
	float snap_pix;
	float aspect;
	float framerate;
	float overscan;
	int thresh_dark;
	int thresh_light;
	int sw_dark;
	int sw_light;
	int decimate;
	int edge_off;
}

/* Declare a property input port of type "Image" and with the key "inputImage" */
@property(assign) id<QCPlugInInputImageSource> inputImage;

@end
