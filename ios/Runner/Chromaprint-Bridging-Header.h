//
//  Chromaprint-Bridging-Header.h
//  Runner
//
//  Chromaprint C 库头文件导入
//

#ifndef Chromaprint_Bridging_Header_h
#define Chromaprint_Bridging_Header_h

#if __has_include(<Chromaprint/chromaprint.h>)
#import <Chromaprint/chromaprint.h>
#define CHROMAPRINT_AVAILABLE 1
#elif __has_include("chromaprint.h")
#import "chromaprint.h"
#define CHROMAPRINT_AVAILABLE 1
#else
#define CHROMAPRINT_AVAILABLE 0
#endif

#endif /* Chromaprint_Bridging_Header_h */
