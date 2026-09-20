//
//  AssetManager.mm
//  MacieWallpaper - Asset Management
//
//  Created on 2026-02-14.
//
//  Objective-C++ so that project.json can be parsed with NSJSONSerialization.
//  The public interface (AssetManager.hpp / Macie::WallpaperProject) is pure
//  C++ and unchanged — only the implementation is platform-aware.
//

#include "AssetManager.hpp"

#import <Foundation/Foundation.h>
#import "Constants.h"

#include <filesystem>

namespace fs = std::filesystem;

namespace Macie {

// ---------------------------------------------------------------------------
#pragma mark - JSON helpers

/// Returns the value for `key` as a std::string, or "" when the key is absent
/// or holds something other than a JSON string.
static std::string StringValue(NSDictionary *json, NSString *key) {
    id value = json[key];
    if (![value isKindOfClass:[NSString class]]) {
        return "";
    }
    return [(NSString *)value UTF8String];
}

/// Returns the value for `key` as a vector of strings. Non-string elements are
/// skipped; a missing or non-array value yields an empty vector.
static std::vector<std::string> StringArrayValue(NSDictionary *json, NSString *key) {
    std::vector<std::string> out;
    id value = json[key];
    if (![value isKindOfClass:[NSArray class]]) {
        return out;
    }
    for (id element in (NSArray *)value) {
        if ([element isKindOfClass:[NSString class]]) {
            out.push_back([(NSString *)element UTF8String]);
        }
    }
    return out;
}

/// Reads a JSON file into a dictionary. Returns nil on any failure.
static NSDictionary *ReadJsonDictionary(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return nil;
    }

    // Some Wallpaper Engine project.json files are written with a UTF-8 BOM,
    // which is not valid JSON. Strip it before parsing.
    static const uint8_t kUtf8Bom[3] = {0xEF, 0xBB, 0xBF};
    if (data.length >= 3 && memcmp(data.bytes, kUtf8Bom, 3) == 0) {
        data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
    }

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        if (error) {
            NSLog(@"AssetManager: could not parse %@: %@", path.lastPathComponent,
                  error.localizedDescription);
        }
        return nil;
    }
    return (NSDictionary *)parsed;
}

// ---------------------------------------------------------------------------
#pragma mark - AssetManager

AssetManager::AssetManager() {
}

AssetManager::~AssetManager() {
}

std::vector<WallpaperProject> AssetManager::scanWallpaperEngine(const std::string& steamappsPath) {
    wallpapers.clear();

    std::string workshopPath = steamappsPath + "/" + [kWorkshopSubpath UTF8String];

    std::error_code ec;
    if (!fs::exists(workshopPath, ec)) {
        NSLog(@"AssetManager: workshop path not found: %s", workshopPath.c_str());
        return wallpapers;
    }

    for (const auto& entry : fs::directory_iterator(workshopPath, ec)) {
        if (!entry.is_directory(ec)) {
            continue;
        }
        auto project = parseProjectJson(entry.path().string());
        if (project.has_value()) {
            wallpapers.push_back(project.value());
        }
    }

    if (ec) {
        NSLog(@"AssetManager: error while scanning %s: %s",
              workshopPath.c_str(), ec.message().c_str());
    }

    NSLog(@"AssetManager: scan complete — %lu video wallpapers found",
          (unsigned long)wallpapers.size());

    return wallpapers;
}

std::optional<WallpaperProject> AssetManager::parseProjectJson(const std::string& folderPath) {
    NSString *folder = [NSString stringWithUTF8String:folderPath.c_str()];
    if (!folder) {
        return std::nullopt;
    }

    NSDictionary *json = ReadJsonDictionary([folder stringByAppendingPathComponent:@"project.json"]);
    if (!json) {
        return std::nullopt;
    }

    // Only video wallpapers are supported. Scene and web types are skipped.
    NSString *type = [json[@"type"] isKindOfClass:[NSString class]]
        ? [(NSString *)json[@"type"] lowercaseString]
        : nil;
    if (![type isEqualToString:@"video"]) {
        return std::nullopt;
    }

    NSString *fileName = [json[@"file"] isKindOfClass:[NSString class]] ? json[@"file"] : nil;
    if (fileName.length == 0) {
        return std::nullopt;
    }

    NSString *videoPath = [folder stringByAppendingPathComponent:fileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        return std::nullopt;
    }

    WallpaperProject project;
    project.id            = fs::path(folderPath).filename().string();
    project.type          = [type UTF8String];
    project.title         = StringValue(json, @"title");
    project.description   = StringValue(json, @"description");
    project.tags          = StringArrayValue(json, @"tags");
    project.videoFilePath = [videoPath UTF8String];

    if (project.title.empty()) {
        project.title = project.id;
    }

    NSString *previewFile = [json[@"preview"] isKindOfClass:[NSString class]] ? json[@"preview"] : nil;
    if (previewFile.length > 0) {
        NSString *previewPath = [folder stringByAppendingPathComponent:previewFile];
        if ([[NSFileManager defaultManager] fileExistsAtPath:previewPath]) {
            project.previewPath = [previewPath UTF8String];
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

} // namespace Macie
