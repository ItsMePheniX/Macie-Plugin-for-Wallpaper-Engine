//
//  ConfigManager.hpp
//  MacieWallpaper - Configuration Management
//
//  Created on 2026-02-14.
//  Note: Placeholder for future JSON-based configuration
//

#pragma once

#include <string>

namespace Macie {

class ConfigManager {
public:
    ConfigManager();
    ~ConfigManager();
    
    void load();
    void save();
    
private:
    std::string configPath;
};

} // namespace Macie
