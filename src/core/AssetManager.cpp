//
//  AssetManager.cpp
//  MacieWallpaper - Asset Management
//
//  Created on 2026-02-14.
//

#include "AssetManager.hpp"
#include <iostream>
#include <fstream>
#include <filesystem>
#include <sstream>
#include <algorithm>

namespace fs = std::filesystem;

namespace Macie {

AssetManager::AssetManager() {
    std::cout << "AssetManager: Constructor" << std::endl;
}

AssetManager::~AssetManager() {
    std::cout << "AssetManager: Destructor" << std::endl;
}

std::vector<WallpaperProject> AssetManager::scanWallpaperEngine(const std::string& steamappsPath) {
    wallpapers.clear();
    
    std::cout << "AssetManager: Scanning Wallpaper Engine directory..." << std::endl;
    std::cout << "  Base path: " << steamappsPath << std::endl;
    
    // Workshop content path
    std::string workshopPath = steamappsPath + "/workshop/content/431960";
    
    if (!fs::exists(workshopPath)) {
        std::cerr << "  ERROR: Workshop path not found: " << workshopPath << std::endl;
        return wallpapers;
    }
    
    int scanned = 0;
    int found = 0;
    
    // Iterate through workshop folders
    std::cout << "  Starting directory iteration..." << std::endl;
    for (const auto& entry : fs::directory_iterator(workshopPath)) {
        if (entry.is_directory()) {
            scanned++;
            std::cout << "  Scanning folder " << scanned << ": " << entry.path().filename() << std::endl;
            auto project = parseProjectJson(entry.path().string());
            if (project.has_value()) {
                // Only add video wallpapers
                if (project->type == "video") {
                    wallpapers.push_back(project.value());
                    found++;
                    std::cout << "  ✓ Found: " << project->title << " (" << project->id << ")" << std::endl;
                } else {
                    std::cout << "  - Skipping (type=" << project->type << ")" << std::endl;
                }
            } else {
                std::cout << "  - No valid project.json" << std::endl;
            }
        }
    }
    
    std::cout << "AssetManager: Scan complete" << std::endl;
    std::cout << "  Folders scanned: " << scanned << std::endl;
    std::cout << "  Video wallpapers found: " << found << std::endl;
    
    return wallpapers;
}

std::optional<WallpaperProject> AssetManager::parseProjectJson(const std::string& folderPath) {
    std::string projectJsonPath = folderPath + "/project.json";
    
    if (!fs::exists(projectJsonPath)) {
        return std::nullopt;
    }
    
    std::ifstream file(projectJsonPath);
    if (!file.is_open()) {
        return std::nullopt;
    }
    
    // Read entire file
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string content = buffer.str();
    file.close();
    
    WallpaperProject project;
    project.id = fs::path(folderPath).filename().string();
    
    size_t typePosition = content.rfind("\"type\"");
    if (typePosition != std::string::npos) {
        size_t valueStart = content.find("\"", typePosition + 6);
        size_t valueEnd = content.find("\"", valueStart + 1);
        if (valueStart != std::string::npos && valueEnd != std::string::npos) {
            project.type = content.substr(valueStart + 1, valueEnd - valueStart - 1);
        }
    }
    
    if (project.type != "video") {
        return std::nullopt;
    }
    
    size_t titlePosition = content.find("\"title\"");
    if (titlePosition != std::string::npos) {
        size_t valueStart = content.find("\"", titlePosition + 7);
        size_t valueEnd = content.find("\"", valueStart + 1);
        if (valueStart != std::string::npos && valueEnd != std::string::npos) {
            project.title = content.substr(valueStart + 1, valueEnd - valueStart - 1);
        }
    }
    
    size_t filePosition = content.find("\"file\"");
    if (filePosition != std::string::npos) {
        size_t valueStart = content.find("\"", filePosition + 6);
        size_t valueEnd = content.find("\"", valueStart + 1);
        if (valueStart != std::string::npos && valueEnd != std::string::npos) {
            std::string fileName = content.substr(valueStart + 1, valueEnd - valueStart - 1);
            project.videoFilePath = folderPath + "/" + fileName;
            
            if (!fs::exists(project.videoFilePath)) {
                return std::nullopt;
            }
        }
    }
    
    size_t descriptionPosition = content.find("\"description\"");
    if (descriptionPosition != std::string::npos) {
        size_t valueStart = content.find("\"", descriptionPosition + 13);
        size_t valueEnd = content.find("\"", valueStart + 1);
        if (valueStart != std::string::npos && valueEnd != std::string::npos) {
            project.description = content.substr(valueStart + 1, valueEnd - valueStart - 1);
        }
    }
    
    size_t previewPosition = content.find("\"preview\"");
    if (previewPosition != std::string::npos) {
        size_t valueStart = content.find("\"", previewPosition + 9);
        size_t valueEnd = content.find("\"", valueStart + 1);
        if (valueStart != std::string::npos && valueEnd != std::string::npos) {
            std::string previewFile = content.substr(valueStart + 1, valueEnd - valueStart - 1);
            project.previewPath = folderPath + "/" + previewFile;
        }
    }
    
    return project;
}

std::vector<WallpaperProject> AssetManager::getVideoWallpapers() const {
    return wallpapers;
}

std::optional<WallpaperProject> AssetManager::getWallpaperById(const std::string& id) const {
    for (const auto& wallpaper : wallpapers) {
        if (wallpaper.id == id) {
            return wallpaper;
        }
    }
    return std::nullopt;
}

bool AssetManager::containsIgnoreCase(const std::string& str, const std::string& substr) const {
    std::string stringLower = str;
    std::string substringLower = substr;
    std::transform(stringLower.begin(), stringLower.end(), stringLower.begin(), ::tolower);
    std::transform(substringLower.begin(), substringLower.end(), substringLower.begin(), ::tolower);
    return stringLower.find(substringLower) != std::string::npos;
}

} // namespace Macie
