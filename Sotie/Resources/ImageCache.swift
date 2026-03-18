//
//  ImageCache.swift
//  Sotie
//
//  Performance optimization for image loading
//

import UIKit

/// Thread-safe image cache for decoded base64 images
actor ImageCache {
  static let shared = ImageCache()

  private var cache: NSCache<NSString, UIImage>

  private init() {
    cache = NSCache<NSString, UIImage>()
    // Limit cache to 100 images
    cache.countLimit = 100
    // Limit to ~50MB
    cache.totalCostLimit = 50 * 1024 * 1024
  }

  func image(forKey key: String) -> UIImage? {
    return cache.object(forKey: key as NSString)
  }

  func setImage(_ image: UIImage, forKey key: String) {
    // Estimate cost based on image dimensions
    let cost = Int(image.size.width * image.size.height * 4)  // 4 bytes per pixel
    cache.setObject(image, forKey: key as NSString, cost: cost)
  }

  func removeImage(forKey key: String) {
    cache.removeObject(forKey: key as NSString)
  }

  func clearCache() {
    cache.removeAllObjects()
  }
}

/// Synchronous image cache for immediate UI updates
class SyncImageCache {
  static let shared = SyncImageCache()

  private let cache: NSCache<NSString, UIImage>
  private let queue = DispatchQueue(label: "\(DeveloperConfig.appBundleID).imagecache", attributes: .concurrent)

  private init() {
    cache = NSCache<NSString, UIImage>()
    cache.countLimit = 100
    cache.totalCostLimit = 50 * 1024 * 1024
  }

  func image(forKey key: String) -> UIImage? {
    var result: UIImage?
    queue.sync {
      result = cache.object(forKey: key as NSString)
    }
    return result
  }

  func setImage(_ image: UIImage, forKey key: String) {
    queue.async(flags: .barrier) { [weak self] in
      let cost = Int(image.size.width * image.size.height * 4)
      self?.cache.setObject(image, forKey: key as NSString, cost: cost)
    }
  }

  func removeImage(forKey key: String) {
    queue.async(flags: .barrier) { [weak self] in
      self?.cache.removeObject(forKey: key as NSString)
    }
  }

  func clearCache() {
    queue.async(flags: .barrier) { [weak self] in
      self?.cache.removeAllObjects()
    }
  }
}
