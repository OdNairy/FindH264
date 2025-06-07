//
//  ContentView.swift
//  FindH264
//
//  Created by odnairy on 7.6.2025.
//

import SwiftUI
import Photos
import AVFoundation
#if os(iOS)
import UIKit
import AVKit
#elseif os(macOS)
import AppKit
import AVKit
#endif

func formatFileSize(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
}

enum SortType: String, CaseIterable, Identifiable {
    case date = "По дате"
    case size = "По размеру"
    case duration = "По длительности"
    var id: String { self.rawValue }
}

struct VideoInfo: Identifiable {
    let id: String
    let asset: PHAsset
    let size: Int64
    let duration: TimeInterval
    let creationDate: Date?
}

struct ContentView: View {
    @State private var videos: [VideoInfo] = []
    @State private var isAuthorized = false
    @State private var isLoading = false
    @State private var selectedVideo: VideoInfo?
    @State private var showingVideoPreview = false
    @State private var sortType: SortType = .size

    var sortedVideos: [VideoInfo] {
        switch sortType {
        case .date:
            return videos.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .size:
            return videos.sorted { $0.size > $1.size }
        case .duration:
            return videos.sorted { $0.duration > $1.duration }
        }
    }

    var totalSize: Int64 {
        videos.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        NavigationView {
            if !isAuthorized {
                VStack {
                    Text("Доступ к фотографиям не разрешен")
                        .font(.headline)
                    Button("Запросить доступ") {
                        requestPhotoLibraryAccess()
                    }
                    .padding()
                }
            } else if isLoading {
                ProgressView("Поиск и обработка видео...")
                    .padding()
            } else {
                VStack(spacing: 8) {
                    Text("Видео: \(sortedVideos.count), общий размер: \(formatFileSize(totalSize))")
                        .font(.subheadline)
                        .padding(.top)
                    Picker("Сортировка", selection: $sortType) {
                        ForEach(SortType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])
                    List(sortedVideos) { video in
                        VideoRow(video: video)
                            .onTapGesture {
                                selectedVideo = video
                                showingVideoPreview = true
                            }
                    }
                    .listStyle(.plain)
                }
                .navigationTitle("H264 Видео")
                .sheet(isPresented: $showingVideoPreview) {
                    if let video = selectedVideo {
                        #if os(iOS)
                        VideoPreviewView(asset: video.asset)
                        #elseif os(macOS)
                        VideoPreviewViewMac(asset: video.asset)
                        #endif
                    }
                }
            }
        }
        .onAppear {
            checkPhotoLibraryAuthorization()
        }
    }

    private func checkPhotoLibraryAuthorization() {
        #if os(iOS)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        isAuthorized = status == .authorized
        if isAuthorized {
            findH264Videos()
        }
        #elseif os(macOS)
        let status = PHPhotoLibrary.authorizationStatus()
        isAuthorized = status == .authorized
        if isAuthorized {
            findH264Videos()
        }
        #endif
    }

    private func requestPhotoLibraryAccess() {
        #if os(iOS)
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                isAuthorized = status == .authorized
                if isAuthorized {
                    findH264Videos()
                }
            }
        }
        #elseif os(macOS)
        // Dummy fetch to trigger system alert
        let _ = PHAsset.fetchAssets(with: .image, options: nil)
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                isAuthorized = status == .authorized
                if isAuthorized {
                    findH264Videos()
                }
            }
        }
        #endif
    }

    private func findH264Videos() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var result: [VideoInfo] = []
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            fetchResult.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                if let videoResource = resources.first(where: { $0.uniformTypeIdentifier == "public.mpeg-4" }) {
                    var size: Int64 = 0
                    if let s = videoResource.value(forKey: "fileSize") as? CLong {
                        size = Int64(s)
                    }
                    let info = VideoInfo(
                        id: asset.localIdentifier,
                        asset: asset,
                        size: size,
                        duration: asset.duration,
                        creationDate: asset.creationDate
                    )
                    result.append(info)
                }
            }
            DispatchQueue.main.async {
                self.videos = result
                self.isLoading = false
            }
        }
    }
}

struct VideoRow: View {
    let video: VideoInfo
    var body: some View {
        HStack {
            #if os(iOS)
            VideoThumbnail(asset: video.asset)
                .frame(width: 60, height: 60)
                .cornerRadius(8)
            #elseif os(macOS)
            VideoThumbnailMac(asset: video.asset)
                .frame(width: 60, height: 60)
                .cornerRadius(8)
            #endif
            VStack(alignment: .leading, spacing: 4) {
                Text("Видео")
                    .font(.headline)
                Text("Длительность: \(formatDuration(video.duration))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Размер: \(formatFileSize(video.size))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(formatDate(video.creationDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Неизвестная дата" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%d сек", seconds)
        }
    }
}

#if os(iOS)
struct VideoPreviewView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            VStack {
                VideoPlayerView(asset: asset)
                    .edgesIgnoringSafeArea(.all)
            }
            .navigationBarItems(trailing: Button("Закрыть") {
                dismiss()
            })
        }
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let asset: PHAsset
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            if let playerItem = playerItem {
                DispatchQueue.main.async {
                    let player = AVPlayer(playerItem: playerItem)
                    controller.player = player
                    player.play()
                }
            }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

struct VideoThumbnail: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    private func generateThumbnail() {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        option.isSynchronous = false
        option.deliveryMode = .highQualityFormat
        manager.requestImage(for: asset,
                           targetSize: CGSize(width: 200, height: 200),
                           contentMode: .aspectFill,
                           options: option) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.thumbnail = image
                }
            }
        }
    }
}
#endif

#if os(macOS)
struct VideoPreviewViewMac: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            VideoPlayerViewMac(asset: asset)
                .frame(minWidth: 600, minHeight: 400)
            Button("Закрыть") {
                dismiss()
            }
            .padding()
        }
        .padding()
    }
}

struct VideoPlayerViewMac: NSViewRepresentable {
    let asset: PHAsset
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            if let playerItem = playerItem {
                DispatchQueue.main.async {
                    let player = AVPlayer(playerItem: playerItem)
                    view.player = player
                    player.play()
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

struct VideoThumbnailMac: View {
    let asset: PHAsset
    @State private var thumbnail: NSImage?
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    private func generateThumbnail() {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        option.isSynchronous = false
        option.deliveryMode = .highQualityFormat
        manager.requestImage(for: asset,
                           targetSize: CGSize(width: 200, height: 200),
                           contentMode: .aspectFill,
                           options: option) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.thumbnail = image
                }
            }
        }
    }
}
#endif

#Preview {
    ContentView()
}
