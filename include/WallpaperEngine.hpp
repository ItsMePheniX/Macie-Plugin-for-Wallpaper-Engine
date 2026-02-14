//
//  WallpaperEngine.hpp
//  MacieWallpaper - Core Engine
//
//  Created on 2026-02-14.
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
