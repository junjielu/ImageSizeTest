//
//  ViewController.swift
//  ImageSizeTest
//
//  Created by 陆俊杰 on 2021/3/23.
//

import UIKit
import Foundation
import MobileCoreServices

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.frame = self.view.bounds
        self.view.addSubview(imageView)
        if let path = Bundle.main.path(forResource: "test", ofType: "jpeg"), let data = NSData(contentsOfFile: path) as Data? {
            let image = ImageUtil.getImage(fromCompressedImageData: data, decodeImage: true)
            imageView.image = image
        }
    }
}

public class ImageUtil {
    public static let imageProcessingQueue = DispatchQueue(label: "com.okjike.imageprocessing")
    public static let maximumImagePixelLimit: CGFloat = 15000000
    
    public static func getImage(fromCompressedImageData data: Data,
                                shortEdgeInPixel: CGFloat? = nil,
                                longEdgeInPixel: CGFloat? = nil,
                                totalPixelLimit: CGFloat = maximumImagePixelLimit,
                                decodeImage: Bool = false) -> UIImage? {
        
        guard let cgImage = self.getDownsampledCGImage(fromCompressedImageData: data,
                                                       shortEdgeInPixel: shortEdgeInPixel,
                                                       longEdgeInPixel: longEdgeInPixel,
                                                       totalPixelLimit: totalPixelLimit,
                                                       decodeImage: decodeImage) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
    }
    
    public enum CompressOption {
        case sizeLimitInKb(Int)
        case compressQuality(Double)
    }
    
    private static func getDownsampledCGImage(fromCompressedImageData data: Data,
                                              shortEdgeInPixel: CGFloat? = nil,
                                              longEdgeInPixel: CGFloat? = nil,
                                              totalPixelLimit: CGFloat,
                                              decodeImage: Bool = false) -> CGImage? {
        guard let imageSource = getImageSource(from: data) else {
            return nil
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
            let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
            let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat else {
        
            return nil
        }
        
        let originalPixelSize = CGSize(width: width, height: height)
        
        var scaledPixelSize = UIImage.calculatePixelSize(originalPixelSize: originalPixelSize, shortEdge: shortEdgeInPixel, longEdge: longEdgeInPixel)
        if scaledPixelSize.width * scaledPixelSize.height > totalPixelLimit {
            let scale = sqrt(scaledPixelSize.width * scaledPixelSize.height / totalPixelLimit)
            scaledPixelSize = CGSize(width: floor(scaledPixelSize.width / scale), height: floor(scaledPixelSize.height / scale))
        }
        
        // see WWDC18 session 219
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(scaledPixelSize.width, scaledPixelSize.height),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: decodeImage,
        ]
        
        guard let resultCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            
            return nil
        }
        
        return resultCGImage
    }
    
    private static func getImageSource(from imageData: Data) -> CGImageSource? {
        // see WWDC18 session 219
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateWithData(imageData as CFData, sourceOptions as CFDictionary)
    }
    
    public static func getImageDataProperties(_ data: Data) -> [String: Any] {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            
            return [:]
        }
        
        return CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] ?? [:]
    }
}

extension Data {
    public var sizeInKb: Int {
        return self.count / 1024
    }
    
    public var sizeInMb: Double {
        return ceil((Double(self.count) / (1024 * 1024)) * 10000) / 10000
    }
}

extension UIImage {
    public static func calculatePixelSize(originalPixelSize: CGSize, shortEdge: CGFloat? = nil, longEdge: CGFloat? = nil) -> CGSize {
        guard shortEdge != nil || longEdge != nil else {
            return originalPixelSize
        }
        
        // validate params
        if let shortEdge = shortEdge, shortEdge <= 0 {
            return originalPixelSize
        }
        
        if let longEdge = longEdge, longEdge <= 0 {
            return originalPixelSize
        }
        
        func getLongEdge(size: CGSize) -> CGFloat {
            return max(size.width, size.height)
        }
        
        func getShortEdge(size: CGSize) -> CGFloat {
            return min(size.width, size.height)
        }
        
        var scaledPixelSize = originalPixelSize
        
        // 1. check if shortEdge is satisfied
        if let toShortEdge = shortEdge {
            if toShortEdge < getShortEdge(size: scaledPixelSize) {
                let scaleDownFactor = toShortEdge / getShortEdge(size: scaledPixelSize)
                scaledPixelSize = scaledPixelSize.applying(CGAffineTransform(scaleX: scaleDownFactor, y: scaleDownFactor))
            }
        }
        
        // 2. check if longEdge is satisfied(after satisfying shortEdge)
        if let toLongEdge = longEdge {
            if toLongEdge < getLongEdge(size: scaledPixelSize) {
                let scaleDownFactor = toLongEdge / getLongEdge(size: scaledPixelSize)
                scaledPixelSize = scaledPixelSize.applying(CGAffineTransform(scaleX: scaleDownFactor, y: scaleDownFactor))
            }
        }
        return scaledPixelSize
    }
    
    /// Scale the image by constraining max short/long edge length in pixel.
    /// - parameter shortEdgeInPixel: Maximum short edge length. nil for unconstrained.
    /// - parameter longEdgeInPixel: Maximum long edge length. nil for unconstrained.
    /// - parameter opaque: If image has alpha channel, set to false. Setting this to false for images without alpha may result in an image with a pink hue.
    /// - returns: Scaled image
    public func limit(shortEdgeInPixel: CGFloat? = nil,
                      longEdgeInPixel: CGFloat? = nil,
                      opaque: Bool = true,
                      resultImageScale: CGFloat? = nil) -> UIImage {
        let originalPixelSize = self.size.applying(CGAffineTransform(scaleX: self.scale, y: self.scale))
        
        let scaledPixelSize = UIImage.calculatePixelSize(originalPixelSize: originalPixelSize, shortEdge: shortEdgeInPixel, longEdge: longEdgeInPixel)
        
        // only return if:
        // 1. pixel size doesn't change after satisfying constraints
        // 2. image scale equals result scale
        if originalPixelSize == scaledPixelSize && (resultImageScale == nil || resultImageScale == self.scale) {
            return self
        }
        
        // draw in scaled canvas
        // current scale is 1, need to render in original image scale(or specified scale), so finally we can get the result image with the desired scale
        // The image scale may be different with the device scale
        let resultImageScale = resultImageScale ?? self.scale
        let factor = 1 / resultImageScale
        let canvasSize = scaledPixelSize.applying(CGAffineTransform(scaleX: factor, y: factor))
        
        UIGraphicsBeginImageContextWithOptions(canvasSize, opaque, resultImageScale)
        self.draw(in: CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resultImage!
    }
    
    public func scale(toSizeInScreenScale: CGSize) -> UIImage {
        let factor = UIScreen.main.scale / self.scale
        let toSizeInSelfScale = CGSize(width: toSizeInScreenScale.width * factor,
                                       height: toSizeInScreenScale.height * factor)
        if toSizeInSelfScale == self.size {
            return self
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: toSizeInScreenScale, format: format).image { _ in
            self.draw(in: CGRect(origin: CGPoint.zero, size: toSizeInScreenScale))
        }
//        UIGraphicsBeginImageContextWithOptions(toSizeInSelfScale, true, self.scale)
//        self.draw(in: CGRect(x: 0, y: 0, width: toSizeInSelfScale.width, height: toSizeInSelfScale.height))
//        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        return resultImage!
    }
    
    /**
     Scale the image by constraining max short/long edge length in point. A wrapper function for limit(shortEdgeInPixel: CGFloat?, longEdgeInPixel: CGFloat?, opaque: Bool)
     */
    public func limitUsingPointOfCurrentDevice(shortEdgeInPoint: CGFloat? = nil, longEdgeInPoint: CGFloat? = nil, opaque: Bool = true) -> UIImage {
        
        let deviceScale = UIScreen.main.scale
        var shortPixel: CGFloat?
        if let short = shortEdgeInPoint {
            shortPixel = short * deviceScale
        }
        var longPixel: CGFloat?
        if let long = longEdgeInPoint {
            longPixel = long * deviceScale
        }
        return limit(shortEdgeInPixel: shortPixel, longEdgeInPixel: longPixel, opaque: opaque, resultImageScale: deviceScale)
    }
}
