#import "libol.h"
#import "trace.h"

#import "QCOpenLaseTracePlugIn.h"

#define	kQCPlugIn_Name				@"QC OpenLase Trace"
#define	kQCPlugIn_Description		@"Drives Laser Projector by vectorized graphics from input image."

@implementation QCOpenLaseTracePlugIn

/* We need to declare the input / output properties as dynamic as Quartz Composer will handle their implementation */
@dynamic inputImage;

+ (NSDictionary*) attributes
{
	/* Return the attributes of this plug-in */
	return [NSDictionary dictionaryWithObjectsAndKeys:kQCPlugIn_Name, QCPlugInAttributeNameKey, kQCPlugIn_Description, QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary*) attributesForPropertyPortWithKey:(NSString*)key
{
	/* Return the attributes for the plug-in property ports */
	if([key isEqualToString:@"inputImage"])
	return [NSDictionary dictionaryWithObjectsAndKeys:@"Image", QCPortAttributeNameKey, nil];
	
	return nil;
}

+ (QCPlugInExecutionMode) executionMode
{
	/* This plug-in is a consumer (it renders to image files) */
	return kQCPlugInExecutionModeConsumer;
}

+ (QCPlugInTimeMode) timeMode
{
	/* This plug-in does not depend on the time (time parameter is completely ignored in the -execute:atTime:withArguments: method) */
	return kQCPlugInTimeModeNone;
}

@end

@implementation QCOpenLaseTracePlugIn (Execution)

#define FRAMES_BUF 8

- (BOOL) startExecution:(id<QCPlugInContext>)context
{
	//NSLog(@"startExecution");
	initialized = false;
	
	return YES;
}

- (BOOL) execute:(id<QCPlugInContext>)context atTime:(NSTimeInterval)timei withArguments:(NSDictionary*)arguments
{
	//NSLog(@"execute:atTime:withArguments:");
	
	id<QCPlugInInputImageSource>	qcImage = self.inputImage;
	NSString*						pixelFormat;
	CGColorSpaceRef					colorSpace;
	CGDataProviderRef				dataProvider;
	CGImageRef						cgImage;
	CGImageDestinationRef			imageDestination;
	NSURL*							fileURL;
	BOOL							success = YES;
	
	/* Make sure we have a new image */
	if(![self didValueForInputKeyChange:@"inputImage"] || !qcImage)
	return YES;

	NSRect bounds = [qcImage imageBounds];
	
	unsigned width = bounds.size.width;
	unsigned height = bounds.size.height;
	//NSLog(@"width:%d height:%d", width, height);
	
	if (!initialized) {
		
		if(olInit(FRAMES_BUF, 300000) < 0) {
			NSLog(@"OpenLase init failed\n");
			return NO;
		}
		
		OLRenderParams params;
		memset(&params, 0, sizeof params);
		params.rate = 48000;
		params.on_speed = 2.0/100.0;
		params.off_speed = 2.0/15.0;
		params.start_wait = 8;
		params.end_wait = 3;
		params.snap = 1/120.0;
		params.render_flags = RENDER_GRAYSCALE;
		params.min_length = 4;
		params.start_dwell = 2;
		params.end_dwell = 2;
		
		params.start_wait = 15;
		//params.end_wait = 0;
		params.start_dwell = 10;
		params.end_dwell = 0;
		//params.corner_dwell = 12;
		params.on_speed = 2.0/100.0;
		params.off_speed = 2.0/20.0;
		
		snap_pix = 3;
		aspect = 0;
		framerate = 30;
		overscan = 0;
		thresh_dark = 60;
		thresh_light = 160;
		sw_dark = 100;
		sw_light = 256;
		decimate = 2;
		edge_off = 0;
		params.min_length = 50;
		
		tparams.mode = OL_TRACE_THRESHOLD;
		tparams.sigma = 0;
		tparams.threshold2 = 50;
		
		tparams.mode = OL_TRACE_CANNY;
		tparams.sigma = 1;
		
		if (aspect == 0)
			aspect = (float)width / height;
		//aspect = pCodecCtx->width / (float)pCodecCtx->height;
		
		//	if (framerate == 0)
		//		framerate = (float)pFormatCtx->streams[videoStream]->r_frame_rate.num / (float)pFormatCtx->streams[videoStream]->r_frame_rate.den;
		
		float iaspect = 1/aspect;
		
		if (aspect > 1) {
			olSetScissor(-1, -iaspect, 1, iaspect);
			olScale(1, iaspect);
		} else {
			olSetScissor(-aspect, -1, aspect, 1);
			olScale(aspect, 1);
		}
		
		//NSLog(@"Aspect is %f %f\n", aspect, iaspect);
		//NSLog(@"Overscan is %f\n", overscan);
		
		olScale(1+overscan, 1+overscan);
		olTranslate(-1.0f, 1.0f);
		olScale(2.0f/width, -2.0f/height);
		
		int maxd = width > height ? width : height;
		params.snap = (snap_pix*2.0)/(float)maxd;
		
		float frametime = 1.0f/framerate;
		//NSLog(@"Framerate: %f (%fs per frame)\n", framerate, frametime);
		
		//olSetAudioCallback(moreaudio);
		olSetRenderParams(&params);
		
		tparams.width = width,
		tparams.height = height,
		olTraceInit(&trace_ctx, &tparams);
		
		initialized = true;
		//NSLog(@"initialized");
	}
	
	pixelFormat = QCPlugInPixelFormatI8;
	colorSpace = CGColorSpaceCreateDeviceGray();
	if(![qcImage lockBufferRepresentationWithPixelFormat:pixelFormat colorSpace:colorSpace forBounds:bounds]) {
		NSLog(@"lockBufferRepresentationWithPixelFormat failed");
		return NO;
	}
	CGColorSpaceRelease(colorSpace);

#if 1
	float vidtime = 0;
	int inf=0;
	int bg_white = -1;
	float time = 0;
	float ftime;
	int frames = 0;

	OLFrameInfo info;	
	OLTraceResult result;	
	memset(&result, 0, sizeof(result));
	float frametime = 1.0f/framerate;
	
	uint8_t *base = (uint8_t *)[qcImage bufferBaseAddress];
	unsigned bytesperrow = [qcImage bufferBytesPerRow];
	
	inf+=1;
	if (vidtime < time) {
		vidtime += frametime;
		printf("Frame skip!\n");
		return YES;
	}
	vidtime += frametime;
	
	int thresh;
	int obj;
	int bsum = 0;
	int c;
	for (c=edge_off; c<(width-edge_off); c++) {
		bsum += base[c+edge_off*bytesperrow];
		bsum += base[c+(height-edge_off-1)*bytesperrow];
	}
	for (c=edge_off; c<(height-edge_off); c++) {
		bsum += base[edge_off+c*bytesperrow];
		bsum += base[(c+1)*bytesperrow-1-edge_off];
	}
	bsum /= (2*(width+height));
	if (bg_white == -1)
		bg_white = bsum > 128;
	if (bg_white && bsum < sw_dark)
		bg_white = 0;
	if (!bg_white && bsum > sw_light)
		bg_white = 1;
	
	if (bg_white)
		thresh = thresh_light;
	else
		thresh = thresh_dark;
	
	tparams.threshold = thresh;
	olTraceReInit(trace_ctx, &tparams);
	olTraceFree(&result);
	obj = olTrace(trace_ctx, base, bytesperrow, &result);
	
	do {
		int i, j;
		for (i = 0; i < result.count; i++) {
			OLTraceObject *o = &result.objects[i];
			olBegin(OL_POINTS);
			OLTracePoint *p = o->points;
			for (j = 0; j < o->count; j++) {
				if (j % decimate == 0)
					olVertex(p->x, p->y, C_WHITE);
				p++;
			}
			olEnd();
		}
		
		ftime = olRenderFrame(200);
		olGetFrameInfo(&info);
		frames++;
		time += ftime;
		printf("Frame time: %.04f, Cur FPS:%6.02f, Avg FPS:%6.02f, Drift: %7.4f, "
			   "In %4d, Out %4d Thr %3d Bg %3d Pts %4d",
			   ftime, 1/ftime, frames/time, time-vidtime,
			   inf, frames, thresh, bsum, info.points);
		if (info.resampled_points)
			printf(" Rp %4d Bp %4d", info.resampled_points, info.resampled_blacks);
		if (info.padding_points)
			printf(" Pad %4d", info.padding_points);
		printf("\n");
	} while ((time+frametime) < vidtime);
	
	/* Release buffer representation */
	[qcImage unlockBufferRepresentation];
#endif
	
	return success;
}

- (void) stopExecution:(id<QCPlugInContext>)context
{
	int i;
	olTraceDeinit(trace_ctx);
	
	for(i=0;i<FRAMES_BUF;i++)
		olRenderFrame(200);
	
	olShutdown();
}
@end
