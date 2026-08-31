//
//  AssetManager.hpp
//  MacieWallpaper - Asset Management
//
//  Created on 2026-02-14.
//

#pragma once

#include <string>
#include <vector>
#include <optional>
#include <functional>

namespace Macie {

struct WallpaperProject {
    std::string id;
    std::string title;
    std::string type;
    std::string videoFilePath;
    std::string previewPath;
    std::string description;
    std::vector<std::string> tags;
};

class AssetManager {
public:
    AssetManager();
    ~AssetManager();

    /// Called once per folder examined, with the running count and the total number
    /// of folders found. Reports work done rather than wallpapers kept, so a library
    /// full of scene wallpapers still advances.
    using ScanProgressCallback = std::function<void(size_t scanned, size_t total)>;

    /// Scans a steamapps directory and returns every video wallpaper in it.
    ///
    /// Static and free of member state, so it is safe to run on a background thread
    /// while another thread reads an instance. Pass the result to adoptWallpapers on
    /// the thread that owns the instance. onProgress is invoked on the calling
    /// thread.
    static std::vector<WallpaperProject> scanWallpaperEngine(
        const std::string& steamappsPath,
        const ScanProgressCallback& onProgress = nullptr);

    /// Replaces the stored list with the result of a scan.
    void adoptWallpapers(std::vector<WallpaperProject> scanned);

    std::vector<WallpaperProject> getVideoWallpapers() const;
    std::optional<WallpaperProject> getWallpaperById(const std::string& id) const;

private:
    std::vector<WallpaperProject> wallpapers;
};

} // namespace Macie
