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
    
    std::vector<WallpaperProject> scanWallpaperEngine(const std::string& steamappsPath);
    std::vector<WallpaperProject> getVideoWallpapers() const;
    std::optional<WallpaperProject> getWallpaperById(const std::string& id) const;
    
private:
    std::vector<WallpaperProject> wallpapers;
    std::optional<WallpaperProject> parseProjectJson(const std::string& folderPath);
    bool containsIgnoreCase(const std::string& str, const std::string& substr) const;
};

} // namespace Macie
