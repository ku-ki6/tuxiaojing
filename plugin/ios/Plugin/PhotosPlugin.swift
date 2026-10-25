import Foundation
import Capacitor
import Photos
import UIKit

/**
 * 图小净 · 相册原生插件
 * 网页版做不到的事，这里全部能做到：
 *   - 读取整个相册（几千张也能读）
 *   - 真删照片（删除后系统相册里同步消失，进"最近删除"）
 */
@objc(PhotosPlugin)
public class PhotosPlugin: CAPPlugin {

    private func statusText(_ s: PHAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "full"
        case .limited:    return "limited"
        case .denied:     return "denied"
        case .restricted: return "restricted"
        default:          return "notDetermined"
        }
    }

    /// 请求相册"读+写"权限（必须 readWrite，否则不能删除）
    @objc func requestPermission(_ call: CAPPluginCall) {
        let cur = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if cur == .authorized || cur == .limited {
            call.resolve(["granted": true, "status": statusText(cur)])
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
            let ok = (s == .authorized || s == .limited)
            call.resolve(["granted": ok, "status": self.statusText(s)])
        }
    }

    /// 当前权限状态
    @objc func checkPermission(_ call: CAPPluginCall) {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        call.resolve(["granted": (s == .authorized || s == .limited), "status": statusText(s)])
    }

    /// 照片总数
    @objc func getCount(_ call: CAPPluginCall) {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: opts)
        call.resolve(["count": assets.count])
    }

    /// 分批读取照片（含缩略图），避免一次取几千张导致内存问题
    @objc func getPhotos(_ call: CAPPluginCall) {
        let offset = call.getInt("offset") ?? 0
        let limit  = min(call.getInt("limit") ?? 200, 500)
        let thumbSize = call.getInt("thumbSize") ?? 256

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: opts)

        if offset >= assets.count {
            call.resolve(["photos": [], "hasMore": false, "total": assets.count])
            return
        }
        let end = min(offset + limit, assets.count)

        let manager = PHImageManager.default()
        let reqOpts = PHImageRequestOptions()
        reqOpts.deliveryMode = .fastFormat
        reqOpts.resizeMode = .fast
        reqOpts.isSynchronous = false
        reqOpts.isNetworkAccessAllowed = true

        let target = CGSize(width: thumbSize, height: thumbSize)
        let lock = NSLock()
        var bucket: [[String: Any]] = []
        let group = DispatchGroup()

        for i in offset..<end {
            let asset = assets.object(at: i)
            group.enter()
            manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: reqOpts) { image, _ in
                defer { group.leave() }
                guard let img = image, let data = img.jpegData(compressionQuality: 0.7) else { return }
                let item: [String: Any] = [
                    "id": asset.localIdentifier,
                    "width": asset.pixelWidth,
                    "height": asset.pixelHeight,
                    "created": asset.creationDate?.timeIntervalSince1970 ?? 0,
                    "bytes": data.count,
                    "mediaSubtype": asset.mediaSubtypes.rawValue,
                    "thumb": "data:image/jpeg;base64," + data.base64EncodedString()
                ]
                lock.lock(); bucket.append(item); lock.unlock()
            }
        }

        group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
            let sorted = bucket
            DispatchQueue.main.async {
                call.resolve([
                    "photos": sorted,
                    "hasMore": end < assets.count,
                    "total": assets.count,
                    "nextOffset": end
                ])
            }
        }
    }

    /// 取单张大图用于预览
    @objc func getImage(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else { call.reject("missing id"); return }
        let maxSize = call.getInt("maxSize") ?? 1024
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { call.reject("photo not found"); return }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: maxSize, height: maxSize),
            contentMode: .aspectFit,
            options: opts
        ) { image, _ in
            guard let img = image, let data = img.jpegData(compressionQuality: 0.85) else {
                call.reject("failed to load image"); return
            }
            call.resolve(["src": "data:image/jpeg;base64," + data.base64EncodedString()])
        }
    }

    /// 真删照片：删除后系统相册同步消失（进"最近删除"，30天内可恢复）
    @objc func deletePhotos(_ call: CAPPluginCall) {
        guard let ids = call.getArray("ids", String.self), !ids.isEmpty else {
            call.reject("missing ids"); return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var list: [PHAsset] = []
        assets.enumerateObjects { a, _, _ in list.append(a) }

        if list.isEmpty { call.resolve(["deleted": 0]); return }

        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(list as NSFastEnumeration)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    call.resolve(["deleted": list.count])
                } else {
                    call.reject("删除失败: \(error?.localizedDescription ?? "未知错误")")
                }
            }
        }
    }
}
