//
//  WallpaperEngine.hpp
//  MacieWallpaper - Core Engine
//
//  Created on 2026-02-14.
//  Note: Placeholder for future scene/web wallpaper support
//

#pragma once

#include <string>
#include <vector>

namespace Macie {

class WallpaperEngine {
public:
    WallpaperEngine();
    ~WallpaperEngine();
    
    void initialize();
    void shutdown();
    
private:
    bool isInitialized;
};

} // namespace Macie
