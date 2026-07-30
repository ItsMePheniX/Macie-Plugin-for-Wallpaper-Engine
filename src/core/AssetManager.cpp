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

// Wallpaper Engine Steam Workshop App ID
static const std::string kWallpaperEngineAppId = "431960";

// ---------------------------------------------------------------------------
// Robust JSON string extractor.
//
// Finds the first occurrence of "key" in the JSON text, then extracts the
// associated string value. Correctly handles \" escape sequences and both
// LF and CRLF line endings (Wallpaper Engine project.json uses CRLF).
//
// Returns an empty string if the key is not found or the value is not a
// well-formed JSON string.
// ---------------------------------------------------------------------------
static std::string extractStringAfterPos(const std::string& json, size_t keyPos, const std::string& token) {
    size_t pos = keyPos + token.size();

    // Skip whitespace, colons, and CR/LF (handles both Unix LF and Windows CRLF)
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t' ||
                                  json[pos] == '\n' || json[pos] == '\r' || json[pos] == ':')) {
        ++pos;
    }

    if (pos >= json.size() || json[pos] != '"') {
        return ""; // Value is not a JSON string
    }
    ++pos; // Move past the opening quote

    // Scan the value character-by-character, respecting backslash escapes
    std::string result;
    while (pos < json.size()) {
        char c = json[pos];
        if (c == '\\' && pos + 1 < json.size()) {
            // Escaped character — include the literal character after the backslash
            char escaped = json[pos + 1];
            switch (escaped) {
                case '"':  result += '"';  break;
                case '\\': result += '\\'; break;
                case '/':  result += '/';  break;
                case 'n':  result += '\n'; break;
                case 'r':  result += '\r'; break;
                case 't':  result += '\t'; break;
                default:   result += escaped; break;
            }
            pos += 2;
        } else if (c == '"') {
            break; // Closing quote — done
        } else {
            result += c;
            ++pos;
        }
    }

    return result;
}

// Finds the FIRST occurrence of "key" and extracts its string value.
static std::string extractJsonStringValue(const std::string& json, const std::string& key) {
    std::string token = "\"" + key + "\"";
    size_t keyPos = json.find(token);
    if (keyPos == std::string::npos) return "";
    return extractStringAfterPos(json, keyPos, token);
}

// ---------------------------------------------------------------------------
// Reverse variant — finds the LAST occurrence of the key.
//
// Required for the top-level "type" field in Wallpaper Engine project.json:
// nested property objects (e.g. schemecolor) always contain their own
// "type":"color" entry that appears BEFORE the top-level "type":"video".
// Using rfind ensures we match the top-level field, not the nested one.
// ---------------------------------------------------------------------------
static std::string extractJsonStringValueReverse(const std::string& json, const std::string& key) {
    std::string token = "\"" + key + "\"";
    size_t keyPos = json.rfind(token);
    if (keyPos == std::string::npos) return "";
    return extractStringAfterPos(json, keyPos, token);
}

AssetManager::AssetManager() {
}

AssetManager::~AssetManager() {
}

std::vector<WallpaperProject> AssetManager::scanWallpaperEngine(const std::string& steamappsPath) {
    wallpapers.clear();

    // Build workshop content path using the Wallpaper Engine App ID
    std::string workshopPath = steamappsPath + "/workshop/content/" + kWallpaperEngineAppId;

    if (!fs::exists(workshopPath)) {
        std::cerr << "Workshop path not found: " << workshopPath << std::endl;
        return wallpapers;
    }

    int foldersScanned = 0;
    int videosFound = 0;

    // Iterate through workshop folders
    for (const auto& entry : fs::directory_iterator(workshopPath)) {
        if (entry.is_directory()) {
            foldersScanned++;
            auto project = parseProjectJson(entry.path().string());
            if (project.has_value()) {
                if (project->type == "video") {
                    wallpapers.push_back(project.value());
                    videosFound++;
                }
            }
        }
    }

    std::cout << "Scan complete: " << videosFound << " videos found" << std::endl;

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

    // "type" uses rfind-based lookup via the Reverse variant because Wallpaper Engine
    // project.json files contain nested objects (e.g. schemecolor) with their own
    // "type":"color" entry that appears before the top-level "type":"video".
    // All other fields use forward find — they are unique within the file.
    project.type        = extractJsonStringValueReverse(content, "type");
    project.title       = extractJsonStringValue(content, "title");
    project.description = extractJsonStringValue(content, "description");

    // Only continue processing if this is a video wallpaper
    if (project.type != "video") {
        return std::nullopt;
    }

    std::string fileName = extractJsonStringValue(content, "file");
    if (fileName.empty()) {
        return std::nullopt;
    }

    project.videoFilePath = folderPath + "/" + fileName;
    if (!fs::exists(project.videoFilePath)) {
        return std::nullopt;
    }

    std::string previewFile = extractJsonStringValue(content, "preview");
    if (!previewFile.empty()) {
        project.previewPath = folderPath + "/" + previewFile;
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

} // namespace Macie
