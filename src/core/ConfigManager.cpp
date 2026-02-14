//
//  ConfigManager.cpp
//  MacieWallpaper - Configuration Management
//
//  Created on 2026-02-14.
//

#include "ConfigManager.hpp"
#include <iostream>

namespace Macie {

ConfigManager::ConfigManager() : configPath("") {
    std::cout << "ConfigManager: Constructor" << std::endl;
}

ConfigManager::~ConfigManager() {
    std::cout << "ConfigManager: Destructor" << std::endl;
}

void ConfigManager::load() {
    std::cout << "ConfigManager: Loading configuration..." << std::endl;
}

void ConfigManager::save() {
    std::cout << "ConfigManager: Saving configuration..." << std::endl;
}

} // namespace Macie
